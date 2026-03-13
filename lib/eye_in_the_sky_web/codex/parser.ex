defmodule EyeInTheSkyWeb.Codex.Parser do
  @moduledoc """
  Parses Codex CLI output in JSONL format.

  Handles JSONL lines from `codex exec --json` and converts them into
  Claude.Message structs for compatibility with the existing message pipeline.

  See `jsonl_schema.json` in this directory for the full JSON Schema of expected events.

  ## Event Types

  - `thread.started` - New thread created (contains thread_id)
  - `turn.started` - Agent turn beginning
  - `item.started` - Item being processed (command_execution, web_search)
  - `item.completed` - Item finished processing
  - `turn.completed` - Agent turn finished (contains usage stats)
  - `turn.failed` - Agent turn failed
  - `error` - Top-level error

  ## Item Types

  - `agent_message` - Text response from the agent
  - `reasoning` - Model thinking/reasoning output
  - `command_execution` - Shell command with command, exit_code, output
  - `file_changes` - File modifications
  - `mcp_tool_calls` - MCP tool invocations
  - `web_search` / `web_searches` - Web search operations
  - `plan_update` / `plan_updates` - Agent plan changes
  """

  alias EyeInTheSkyWeb.Claude.Message
  require Logger

  @doc """
  Parse a single line of Codex JSONL output.

  Returns:
  - `{:ok, %Message{}}` - successfully parsed message
  - `{:session_id, thread_id}` - extracted thread/session ID
  - `{:result, map}` - turn completed with usage metadata
  - `{:error, reason}` - parse error or Codex error
  - `:skip` - line should be ignored (non-JSON, turn.started, etc.)
  """
  @spec parse_stream_line(String.t()) ::
          {:ok, Message.t()}
          | {:session_id, String.t()}
          | {:result, map()}
          | {:error, term()}
          | :skip
  def parse_stream_line(line) when is_binary(line) do
    line = String.trim(line)

    if line == "" do
      :skip
    else
      case Jason.decode(line) do
        {:ok, json} ->
          parse_event(json)

        {:error, _reason} ->
          # Non-JSON lines (stderr, tracing output) are expected; skip them
          :skip
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Event dispatch
  # ---------------------------------------------------------------------------

  # Thread started - extract thread_id as session identifier
  defp parse_event(%{"type" => "thread.started", "thread_id" => thread_id}) do
    {:session_id, thread_id}
  end

  # Turn started - no actionable data
  defp parse_event(%{"type" => "turn.started"}) do
    :skip
  end

  # Item started - only emit for command_execution (shows tool in-progress)
  defp parse_event(%{"type" => "item.started", "item" => %{"type" => "command_execution"} = item}) do
    input = %{
      command: item["command"] || item["call"] || "",
      working_directory: item["working_directory"]
    }

    {:ok, Message.tool_use("command_execution", input, %{partial: true})}
  end

  defp parse_event(%{"type" => "item.started", "item" => %{"type" => type} = item})
       when type in ["web_search", "web_searches"] do
    {:ok, Message.tool_use(type, item, %{partial: true})}
  end

  defp parse_event(%{"type" => "item.started"}) do
    :skip
  end

  # Item completed - reasoning (thinking)
  defp parse_event(%{
         "type" => "item.completed",
         "item" => %{"type" => "reasoning", "text" => text}
       })
       when is_binary(text) and text != "" do
    {:ok, Message.thinking(text, false)}
  end

  defp parse_event(%{
         "type" => "item.completed",
         "item" => %{"type" => "reasoning", "content" => content}
       })
       when is_list(content) do
    text = extract_text_from_content(content)

    if text != "" do
      {:ok, Message.thinking(text, false)}
    else
      :skip
    end
  end

  # Item completed - agent_message (assistant text response)
  defp parse_event(%{
         "type" => "item.completed",
         "item" => %{"type" => "agent_message", "text" => text}
       })
       when is_binary(text) and text != "" do
    {:ok, Message.text(text, false)}
  end

  defp parse_event(%{
         "type" => "item.completed",
         "item" => %{"type" => "agent_message", "content" => content}
       })
       when is_list(content) do
    text = extract_text_from_content(content)

    if text != "" do
      {:ok, Message.text(text, false)}
    else
      :skip
    end
  end

  # Item completed - command_execution (tool use)
  defp parse_event(%{
         "type" => "item.completed",
         "item" => %{"type" => "command_execution"} = item
       }) do
    input = %{
      command: item["command"] || item["call"] || "",
      exit_code: item["exit_code"],
      output: item["aggregated_output"] || item["output"],
      working_directory: item["working_directory"]
    }

    {:ok, Message.tool_use("command_execution", input)}
  end

  # Item completed - file_changes (tool use)
  defp parse_event(%{
         "type" => "item.completed",
         "item" => %{"type" => "file_changes"} = item
       }) do
    {:ok, Message.tool_use("file_changes", item)}
  end

  # Item completed - mcp_tool_calls (tool use)
  defp parse_event(%{
         "type" => "item.completed",
         "item" => %{"type" => "mcp_tool_calls"} = item
       }) do
    {:ok, Message.tool_use("mcp_tool_calls", item)}
  end

  # Item completed - web_search (tool use)
  defp parse_event(%{
         "type" => "item.completed",
         "item" => %{"type" => "web_search"} = item
       }) do
    {:ok, Message.tool_use("web_search", item)}
  end

  defp parse_event(%{
         "type" => "item.completed",
         "item" => %{"type" => "web_searches"} = item
       }) do
    {:ok, Message.tool_use("web_searches", item)}
  end

  # Item completed - plan_update (tool use)
  defp parse_event(%{
         "type" => "item.completed",
         "item" => %{"type" => "plan_update"} = item
       }) do
    {:ok, Message.tool_use("plan_update", item)}
  end

  defp parse_event(%{
         "type" => "item.completed",
         "item" => %{"type" => "plan_updates"} = item
       }) do
    {:ok, Message.tool_use("plan_updates", item)}
  end

  # Item completed - other types
  defp parse_event(%{"type" => "item.completed"} = event) do
    Logger.debug(
      "[Codex.Parser] Unhandled item.completed type: #{inspect(event["item"]["type"])}"
    )

    :skip
  end

  # Turn completed - contains usage stats, acts as result signal
  defp parse_event(%{"type" => "turn.completed"} = event) do
    usage = event["usage"] || %{}

    data = %{
      input_tokens: usage["input_tokens"] || 0,
      output_tokens: usage["output_tokens"] || 0,
      total_tokens: usage["total_tokens"] || 0,
      usage: usage,
      session_id: event["thread_id"]
    }

    {:result, data}
  end

  # Turn failed
  defp parse_event(%{"type" => "turn.failed"} = event) do
    message = event["message"] || event["error"] || "Turn failed"
    {:error, {:turn_failed, message}}
  end

  # Top-level error
  defp parse_event(%{"type" => "error"} = event) do
    message = event["message"] || event["error"] || "Unknown error"
    {:error, {:codex_error, message}}
  end

  # Error object without type
  defp parse_event(%{"error" => error}) when is_binary(error) do
    {:error, {:codex_error, error}}
  end

  defp parse_event(%{"error" => %{"message" => message}}) do
    {:error, {:codex_error, message}}
  end

  # Unknown event type
  defp parse_event(_other) do
    :skip
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp extract_text_from_content(content) when is_list(content) do
    content
    |> Enum.filter(fn
      %{"type" => "text"} -> true
      %{"type" => "output_text"} -> true
      _ -> false
    end)
    |> Enum.map_join("", fn item -> item["text"] || "" end)
  end

  defp extract_text_from_content(_), do: ""
end
