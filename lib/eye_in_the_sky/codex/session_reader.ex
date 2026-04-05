defmodule EyeInTheSky.Codex.SessionReader do
  @moduledoc """
  Reads Codex session files from ~/.codex/sessions/ and extracts conversation messages.

  Codex session files differ from Claude's format:
  - Stored at ~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<thread_id>.jsonl
  - Events are wrapped as {"type": "event_msg", "payload": {...}, "timestamp": "..."}
  - Relevant payload types: "session_meta", "user_message", "agent_message", "token_count"
  """

  require Logger

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

      {:ok, messages}
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

  defp extract_message(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "event_msg", "payload" => payload, "timestamp" => timestamp}} ->
        extract_payload_message(payload, timestamp)

      {:ok, %{"type" => "event_msg", "payload" => payload}} ->
        extract_payload_message(payload, nil)

      _ ->
        []
    end
  end

  defp extract_payload_message(%{"type" => "user_message", "message" => text}, timestamp)
       when is_binary(text) and text != "" do
    [
      %{
        uuid: derive_uuid(text, timestamp),
        role: "user",
        content: text,
        timestamp: timestamp,
        usage: nil,
        stream_type: nil
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
        stream_type: nil
      }
    ]
  end

  defp extract_payload_message(_payload, _timestamp), do: []

  # Derive a stable UUID from content + timestamp so deduplication works across syncs.
  defp derive_uuid(content, timestamp) do
    seed = "#{timestamp}:#{content}"
    hex = :crypto.hash(:sha, seed) |> Base.encode16(case: :lower)

    "#{String.slice(hex, 0, 8)}-#{String.slice(hex, 8, 4)}-#{String.slice(hex, 12, 4)}-#{String.slice(hex, 16, 4)}-#{String.slice(hex, 20, 12)}"
  end
end
