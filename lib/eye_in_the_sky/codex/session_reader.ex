defmodule EyeInTheSky.Codex.SessionReader do
  @moduledoc """
  Reads Codex session files from ~/.codex/sessions/ and extracts conversation messages.

  Codex session files differ from Claude's format:
  - Stored at ~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<thread_id>.jsonl
  - Events are wrapped as {"type": "event_msg", "payload": {...}, "timestamp": "..."}
  - Relevant payload types: "session_meta", "user_message", "agent_message", "token_count"
  """

  alias EyeInTheSky.Codex.Error

  @doc """
  Finds the Codex session JSONL file for a given thread_id.
  Codex stores sessions in: ~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<thread_id>.jsonl
  """
  @spec find_session_file(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def find_session_file(nil), do: {:error, :not_found}

  def find_session_file(thread_id) when is_binary(thread_id) do
    home = System.get_env("HOME")
    sessions_dir = Path.join([home, ".codex", "sessions"])
    pattern = Path.join([sessions_dir, "**", "*#{thread_id}.jsonl"])

    case Path.wildcard(pattern) do
      [file | _] -> {:ok, file}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Reads all messages from a Codex session file.
  Returns {:ok, messages} where each message is a map with :role, :content, :timestamp, :uuid.
  """
  @spec read_messages(String.t()) :: {:ok, list(map())} | {:error, term()}
  def read_messages(thread_id) do
    with {:ok, file_path} <- find_session_file(thread_id),
         {:ok, content} <- File.read(file_path) do
      messages =
        content
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&extract_message/1)
        |> dedupe_messages()

      {:ok, messages}
    end
  end

  @doc """
  Reads Codex messages from the thread file whose UUIDs come after `after_uuid`.
  If `after_uuid` is nil, reads all messages. If `after_uuid` is not found in the
  file (e.g., file rotated), reads all messages. Used for incremental sync.
  """
  @spec read_messages_after_uuid(String.t(), String.t() | nil) ::
          {:ok, list(map())} | {:error, term()}
  def read_messages_after_uuid(thread_id, after_uuid) do
    with {:ok, messages} <- read_messages(thread_id) do
      {:ok, drop_messages_before(messages, after_uuid)}
    end
  end

  @doc """
  Reads total token usage from the last token_count event in the session file.
  Returns {:ok, total_tokens, cost_usd} — Codex does not expose cost, so cost is always 0.0.
  """
  @spec read_usage(String.t()) :: {:ok, non_neg_integer(), float()} | {:error, term()}
  def read_usage(thread_id) do
    with {:ok, file_path} <- find_session_file(thread_id),
         {:ok, content} <- File.read(file_path) do
      total_tokens =
        content
        |> String.split("\n", trim: true)
        |> Enum.reduce(0, &count_tokens_in_line/2)

      {:ok, total_tokens, 0.0}
    end
  end

  defp count_tokens_in_line(line, acc) do
    case Jason.decode(line) do
      {:ok, %{"type" => "event_msg", "payload" => %{"type" => "token_count"} = payload}} ->
        get_in(payload, ["info", "total_token_usage", "total_tokens"]) || acc

      _ ->
        acc
    end
  end

  @doc """
  Formats already-parsed messages for use by SessionImporter.
  Since read_messages/1 already returns structured maps, this is an identity function.
  """
  def format_messages(messages) when is_list(messages), do: messages

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp drop_messages_before(messages, nil), do: messages

  defp drop_messages_before(messages, after_uuid) do
    case Enum.find_index(messages, fn msg -> msg.uuid == after_uuid end) do
      nil -> messages
      idx -> Enum.drop(messages, idx + 1)
    end
  end

  defp extract_message(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "response_item", "payload" => payload, "timestamp" => timestamp}} ->
        extract_response_item(payload, timestamp)

      {:ok, %{"type" => "response_item", "payload" => payload}} ->
        extract_response_item(payload, nil)

      {:ok, %{"type" => "turn.failed"} = event} ->
        extract_turn_failed(event, event["timestamp"])

      {:ok, %{"type" => "error"} = event} ->
        extract_codex_error(event, event["timestamp"])

      {:ok, %{"error" => _error} = event} ->
        extract_codex_error(event, event["timestamp"])

      {:ok, %{"type" => "event_msg", "payload" => payload, "timestamp" => timestamp}} ->
        extract_payload_message(payload, timestamp)

      {:ok, %{"type" => "event_msg", "payload" => payload}} ->
        extract_payload_message(payload, nil)

      _ ->
        []
    end
  end

  defp extract_response_item(
         %{"type" => "message", "role" => role, "content" => content} = payload,
         timestamp
       )
       when role in ["user", "assistant"] do
    text = content_text(content)

    if text == "" do
      []
    else
      [
        %{
          uuid: source_uuid(payload["id"], text, timestamp),
          role: role,
          content: text,
          timestamp: timestamp,
          usage: nil,
          stream_type: nil,
          metadata: %{"codex_item_type" => "message"}
        }
      ]
    end
  end

  defp extract_response_item(%{"type" => "reasoning"} = payload, timestamp) do
    text = content_text(payload["text"] || payload["content"])

    if text == "" do
      []
    else
      [
        %{
          uuid: source_uuid(payload["id"], "reasoning:#{text}", timestamp),
          role: "assistant",
          content: text,
          timestamp: timestamp,
          usage: nil,
          stream_type: "thinking",
          metadata: %{
            "codex_item_type" => "reasoning",
            "stream_type" => "thinking",
            "thinking" => text
          }
        }
      ]
    end
  end

  defp extract_response_item(%{"type" => "command_execution"} = payload, timestamp) do
    input = %{
      "command" => payload["command"] || payload["call"] || "",
      "exit_code" => payload["exit_code"],
      "output" => payload["aggregated_output"] || payload["output"],
      "working_directory" => payload["working_directory"]
    }

    [tool_message(payload, timestamp, "Bash", input)]
  end

  defp extract_response_item(%{"type" => type} = payload, timestamp)
       when type in [
              "file_change",
              "file_changes",
              "mcp_tool_call",
              "mcp_tool_calls",
              "web_search",
              "web_searches",
              "plan_update",
              "plan_updates"
            ] do
    [tool_message(payload, timestamp, codex_tool_label(type), payload)]
  end

  defp extract_response_item(_payload, _timestamp), do: []

  defp extract_payload_message(%{"type" => "user_message", "message" => text}, timestamp)
       when is_binary(text) and text != "" do
    [
      %{
        uuid: derive_uuid(text, timestamp),
        role: "user",
        content: text,
        timestamp: timestamp,
        usage: nil,
        stream_type: nil,
        metadata: %{"codex_item_type" => "legacy_user_message"}
      }
    ]
  end

  defp extract_payload_message(%{"type" => "agent_message", "message" => text}, timestamp)
       when is_binary(text) and text != "" do
    [
      %{
        uuid: derive_uuid(text, timestamp),
        role: "assistant",
        content: text,
        timestamp: timestamp,
        usage: nil,
        stream_type: nil,
        metadata: %{"codex_item_type" => "legacy_agent_message"}
      }
    ]
  end

  defp extract_payload_message(%{"type" => "turn.failed"} = payload, timestamp) do
    extract_turn_failed(payload, timestamp)
  end

  defp extract_payload_message(%{"type" => "error"} = payload, timestamp) do
    extract_codex_error(payload, timestamp)
  end

  defp extract_payload_message(_payload, _timestamp), do: []

  defp content_text(content) when is_binary(content), do: String.trim(content)

  defp content_text(content) when is_list(content) do
    content
    |> Enum.flat_map(fn
      %{"text" => text} when is_binary(text) -> [text]
      _ -> []
    end)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp content_text(_content), do: ""

  defp tool_message(payload, timestamp, label, input) do
    compact_input = compact_json(input)
    encoded_input = Jason.encode!(compact_input)

    %{
      uuid: source_uuid(payload["id"], "#{payload["type"]}:#{encoded_input}", timestamp),
      role: "assistant",
      content: "Tool: #{label}\n#{encoded_input}",
      timestamp: timestamp,
      usage: nil,
      stream_type: "tool_use",
      metadata:
        %{
          "codex_item_type" => payload["type"],
          "stream_type" => "tool_use",
          "tool_name" => label,
          "input" => compact_input,
          "exit_code" => Map.get(compact_input, "exit_code")
        }
        |> compact_json()
    }
  end

  defp extract_turn_failed(event, timestamp) do
    normalized = Error.normalize(event, "Turn failed")
    message = normalized.message

    [
      %{
        uuid: source_uuid(event["id"], "turn_failed:#{message}", timestamp),
        role: "assistant",
        content: message,
        timestamp: timestamp,
        usage: nil,
        stream_type: "codex_turn_failed",
        metadata:
          %{
            "codex_item_type" => "turn.failed",
            "stream_type" => "codex_turn_failed",
            "error_title" => "Codex turn failed",
            "error_message" => message,
            "status" => normalized.status,
            "error_type" => normalized.error_type,
            "model" => normalized.model
          }
          |> compact_json()
      }
    ]
  end

  defp extract_codex_error(event, timestamp) do
    normalized = Error.normalize(event, "Unknown error")
    message = normalized.message

    [
      %{
        uuid: source_uuid(event["id"], "codex_error:#{message}", timestamp),
        role: "assistant",
        content: message,
        timestamp: timestamp,
        usage: nil,
        stream_type: "codex_error",
        metadata:
          %{
            "codex_item_type" => "error",
            "stream_type" => "codex_error",
            "error_title" => "Codex error",
            "error_message" => message,
            "status" => normalized.status,
            "error_type" => normalized.error_type,
            "model" => normalized.model
          }
          |> compact_json()
      }
    ]
  end

  defp codex_tool_label("command_execution"), do: "Bash"
  defp codex_tool_label("web_search"), do: "WebSearch"
  defp codex_tool_label("web_searches"), do: "WebSearch"
  defp codex_tool_label("mcp_tool_call"), do: "MCP Tool"
  defp codex_tool_label("mcp_tool_calls"), do: "MCP Tool"

  defp codex_tool_label(type) when is_binary(type) do
    type
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp compact_json(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp compact_json(value), do: value

  defp dedupe_messages(messages) do
    {_seen, deduped} =
      Enum.reduce(messages, {MapSet.new(), []}, fn msg, {seen, acc} ->
        if MapSet.member?(seen, msg.uuid) do
          {seen, acc}
        else
          {MapSet.put(seen, msg.uuid), [msg | acc]}
        end
      end)

    Enum.reverse(deduped)
  end

  defp source_uuid(id, _content, _timestamp) when is_binary(id) and id != "" do
    hash_to_uuid(id)
  end

  defp source_uuid(_id, content, timestamp), do: derive_uuid(content, timestamp)

  # Derive a stable UUID from content + timestamp so deduplication works across syncs.
  defp derive_uuid(content, timestamp) do
    seed = "#{timestamp}:#{content}"
    hash_to_uuid(seed)
  end

  defp hash_to_uuid(seed) do
    hex = :crypto.hash(:sha, seed) |> Base.encode16(case: :lower)

    "#{String.slice(hex, 0, 8)}-#{String.slice(hex, 8, 4)}-#{String.slice(hex, 12, 4)}-#{String.slice(hex, 16, 4)}-#{String.slice(hex, 20, 12)}"
  end
end
