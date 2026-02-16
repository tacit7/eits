defmodule EyeInTheSkyWeb.Claude.Parser do
  @moduledoc """
  Parses Claude CLI output in stream-json format.

  Handles NDJSON lines from `claude --output-format stream-json` and converts
  them into Message structs.
  """

  alias EyeInTheSkyWeb.Claude.Message

  require Logger

  @doc """
  Parse a single line of stream-json output.

  Returns:
  - `{:ok, %Message{}}` - successfully parsed message
  - `{:session_id, session_id}` - extracted session ID
  - `{:result, data}` - conversation result with text, uuid, cost, duration
  - `{:complete, session_id}` - conversation complete
  - `{:error, reason}` - parse error or Claude error
  - `:skip` - line should be ignored
  """
  @spec parse_stream_line(String.t()) ::
          {:ok, Message.t()}
          | {:session_id, String.t()}
          | {:result, map()}
          | {:complete, String.t() | nil}
          | {:error, term()}
          | :skip
  def parse_stream_line(line) when is_binary(line) do
    line = String.trim(line)

    if line == "" do
      :skip
    else
      case Jason.decode(line) do
        {:ok, json} -> parse_event(json)
        {:error, reason} -> {:error, {:json_decode_error, reason}}
      end
    end
  end

  # Parse different event types from stream-json
  defp parse_event(%{"type" => "init", "session_id" => session_id}) do
    {:session_id, session_id}
  end

  defp parse_event(%{"type" => "system", "subtype" => "init", "session_id" => session_id}) do
    {:session_id, session_id}
  end

  defp parse_event(%{"type" => "system"}) do
    # Hook messages and other system events - skip
    :skip
  end

  defp parse_event(%{"type" => "stream_event", "event" => event}) do
    parse_stream_event(event)
  end

  defp parse_event(%{"type" => "assistant", "message" => %{"content" => content}}) do
    text = extract_text_from_content(content)
    tool_name = extract_tool_from_content(content)

    cond do
      tool_name ->
        {:ok, Message.tool_use(tool_name, %{}, %{text: text})}

      text != "" ->
        {:ok, Message.text(text, false)}

      true ->
        :skip
    end
  end

  defp parse_event(%{"type" => "error", "error" => error}) do
    {:error, parse_error(error)}
  end

  defp parse_event(%{"type" => "result"} = event) do
    result_text = event["result"]

    data = %{
      session_id: event["session_id"],
      result: result_text,
      uuid: event["uuid"],
      duration_ms: event["duration_ms"],
      total_cost_usd: event["total_cost_usd"],
      usage: event["usage"],
      model_usage: event["modelUsage"],
      num_turns: event["num_turns"],
      is_error: event["is_error"],
      errors: event["errors"] || event["error"]
    }

    {:result, data}
  end

  defp parse_event(%{"error" => error}) do
    {:error, parse_error(error)}
  end

  defp parse_event(_other) do
    # Unknown event type - skip
    :skip
  end

  # Parse stream events (deltas during generation)
  defp parse_stream_event(%{"type" => "content_block_start", "content_block" => block}) do
    case block do
      %{"type" => "text"} ->
        :skip

      %{"type" => "thinking"} ->
        :skip

      %{"type" => "tool_use", "name" => name, "id" => id} ->
        {:ok, Message.tool_use(name, %{}, %{id: id, partial: true})}

      _ ->
        :skip
    end
  end

  defp parse_stream_event(%{"type" => "content_block_delta", "delta" => delta}) do
    case delta do
      %{"type" => "text_delta", "text" => text} ->
        {:ok, Message.text(text, true)}

      %{"type" => "thinking_delta", "thinking" => thinking} ->
        {:ok, Message.thinking(thinking, true)}

      %{"type" => "input_json_delta", "partial_json" => json} ->
        # Tool input being streamed
        {:ok, %Message{type: :tool_use, content: json, delta: true}}

      _ ->
        :skip
    end
  end

  defp parse_stream_event(%{"type" => "content_block_stop"}) do
    :skip
  end

  defp parse_stream_event(%{"type" => "message_start"}) do
    :skip
  end

  defp parse_stream_event(%{"type" => "message_delta", "delta" => _delta, "usage" => usage}) do
    output_tokens = usage["output_tokens"] || 0
    {:ok, Message.usage(0, output_tokens)}
  end

  defp parse_stream_event(%{"type" => "message_stop"}) do
    # message_stop within a stream_event means one assistant message ended,
    # NOT that the whole conversation is done. The actual end is signaled by
    # the top-level "result" event or process exit.
    :skip
  end

  defp parse_stream_event(_other) do
    :skip
  end

  # Extract text from content blocks array
  defp extract_text_from_content(content) when is_list(content) do
    content
    |> Enum.filter(&match?(%{"type" => "text"}, &1))
    |> Enum.map_join("", & &1["text"])
  end

  defp extract_text_from_content(_), do: ""

  defp extract_tool_from_content(content) when is_list(content) do
    Enum.find_value(content, fn
      %{"type" => "tool_use", "name" => name} -> name
      _ -> nil
    end)
  end

  defp extract_tool_from_content(_), do: nil

  # Parse error objects
  defp parse_error(%{"type" => type, "message" => message}) do
    {String.to_atom(type), message}
  end

  defp parse_error(%{"message" => message}) do
    {:unknown_error, message}
  end

  defp parse_error(error) when is_binary(error) do
    {:unknown_error, error}
  end

  defp parse_error(error) do
    {:unknown_error, inspect(error)}
  end
end
