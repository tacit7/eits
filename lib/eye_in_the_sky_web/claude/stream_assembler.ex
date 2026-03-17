defmodule EyeInTheSkyWeb.Claude.StreamAssembler do
  @moduledoc """
  Pure data module that owns stream assembly state for the AgentWorker.

  Accumulates text deltas into a buffer, tracks the current tool block,
  and decodes tool input JSON. Returns `{updated_stream, events}` tuples
  where events are PubSub-ready messages the caller broadcasts.
  """

  alias EyeInTheSkyWeb.Claude.Message

  @type event ::
          {:stream_delta, :text, String.t()}
          | {:stream_replace, :text, String.t()}
          | {:stream_delta, :tool_use, String.t()}
          | {:stream_delta, :thinking, nil}
          | {:stream_replace, :thinking, String.t()}
          | {:stream_tool_input, String.t(), map() | %{raw: String.t()}}

  @type t :: %__MODULE__{
          buffer: String.t(),
          tool_id: String.t() | nil,
          tool_name: String.t() | nil,
          tool_input: String.t()
        }

  defstruct buffer: "",
            tool_id: nil,
            tool_name: nil,
            tool_input: ""

  @doc "Create a fresh stream assembler."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Reset all stream state (after SDK completes or errors)."
  @spec reset(t()) :: t()
  def reset(%__MODULE__{}), do: %__MODULE__{}

  @doc "Get the current text buffer."
  @spec buffer(t()) :: String.t()
  def buffer(%__MODULE__{buffer: buf}), do: buf

  @doc """
  Handle a tool input delta — accumulate raw JSON chunk, no events emitted.
  """
  @spec handle_tool_delta(t(), String.t()) :: {t(), []}
  def handle_tool_delta(%__MODULE__{} = stream, json) when is_binary(json) do
    {%{stream | tool_input: stream.tool_input <> json}, []}
  end

  @doc """
  Handle a tool block stop — decode accumulated input and emit tool_input event.
  Returns `{updated_stream, events}`.
  """
  @spec handle_tool_block_stop(t()) :: {t(), [event()]}
  def handle_tool_block_stop(%__MODULE__{tool_id: nil} = stream), do: {stream, []}

  def handle_tool_block_stop(%__MODULE__{tool_id: _id, tool_name: name, tool_input: raw} = stream) do
    input =
      case Jason.decode(raw) do
        {:ok, decoded} -> decoded
        {:error, _} -> %{raw: raw}
      end

    {%{stream | tool_id: nil, tool_name: nil, tool_input: ""}, [{:stream_tool_input, name, input}]}
  end

  @doc """
  Handle a generic SDK message. Updates stream state and returns events to broadcast.
  Handles tool starts, text deltas/replacements, tool use names, and thinking blocks.
  """
  @spec handle_message(t(), Message.t()) :: {t(), [event()]}
  def handle_message(%__MODULE__{} = stream, %Message{} = msg) do
    stream = maybe_start_tool(stream, msg)
    events = events_for(msg)
    stream = update_buffer(stream, msg)
    {stream, events}
  end

  # --- Private ---

  # Track the start of a tool block so we can accumulate its input
  defp maybe_start_tool(stream, %Message{
         type: :tool_use,
         delta: false,
         content: %{name: name},
         metadata: %{id: id}
       }) do
    %{stream | tool_id: id, tool_name: name, tool_input: ""}
  end

  defp maybe_start_tool(stream, _msg), do: stream

  # Text delta
  defp events_for(%Message{type: :text, content: text, delta: true}) when is_binary(text) do
    [{:stream_delta, :text, text}]
  end

  # Cumulative text replacement
  defp events_for(%Message{type: :text, content: text, delta: false})
       when is_binary(text) and text != "" do
    [{:stream_replace, :text, text}]
  end

  # Tool use with name in content map
  defp events_for(%Message{type: :tool_use, content: %{name: name}}) when is_binary(name) do
    [{:stream_delta, :tool_use, name}]
  end

  # Tool use with name as string content
  defp events_for(%Message{type: :tool_use, content: name}) when is_binary(name) do
    [{:stream_delta, :tool_use, name}]
  end

  # Thinking delta
  defp events_for(%Message{type: :thinking, delta: true}) do
    [{:stream_delta, :thinking, nil}]
  end

  # Thinking block (complete)
  defp events_for(%Message{type: :thinking, content: text, delta: false})
       when is_binary(text) and text != "" do
    [{:stream_replace, :thinking, text}]
  end

  defp events_for(_msg), do: []

  # Buffer accumulation
  defp update_buffer(stream, %Message{type: :text, content: text, delta: true})
       when is_binary(text) do
    %{stream | buffer: stream.buffer <> text}
  end

  defp update_buffer(stream, %Message{type: :text, content: text, delta: false})
       when is_binary(text) do
    %{stream | buffer: text}
  end

  defp update_buffer(stream, _msg), do: stream
end
