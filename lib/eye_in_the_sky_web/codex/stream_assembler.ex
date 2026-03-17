defmodule EyeInTheSkyWeb.Codex.StreamAssembler do
  @moduledoc """
  Stream assembler for Codex provider.

  Unlike Claude's delta-based streaming, Codex emits complete items via JSONL.
  Text arrives as full blocks, tool events carry rich metadata (command output,
  exit codes, file changes), and Codex has item types Claude doesn't have
  (plan_update, web_search, file_changes).

  Implements the same interface as `Claude.StreamAssembler` so the AgentWorker
  can dispatch to either without branching:

    * `new/0`, `reset/1`, `buffer/1`
    * `handle_message/2` → `{updated_stream, events}`
    * `handle_tool_delta/2` → `{updated_stream, []}`
    * `handle_tool_block_stop/1` → `{updated_stream, events}`

  Events emitted use the same PubSub tuple format so DmLive doesn't care
  which provider it's listening to.
  """

  alias EyeInTheSkyWeb.Claude.Message

  @type event ::
          {:stream_replace, :text, String.t()}
          | {:stream_delta, :tool_use, String.t()}
          | {:stream_replace, :thinking, String.t()}
          | {:stream_tool_input, String.t(), map()}
          | {:stream_replace, :tool_output, map()}

  @type t :: %__MODULE__{
          buffer: String.t(),
          tool_name: String.t() | nil,
          last_tool: map() | nil
        }

  defstruct buffer: "",
            tool_name: nil,
            last_tool: nil

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec reset(t()) :: t()
  def reset(%__MODULE__{}), do: %__MODULE__{}

  @spec buffer(t()) :: String.t()
  def buffer(%__MODULE__{buffer: buf}), do: buf

  @doc """
  No-op for Codex — tool input arrives complete, not as streaming deltas.
  Kept for interface compatibility with Claude.StreamAssembler.
  """
  @spec handle_tool_delta(t(), String.t()) :: {t(), []}
  def handle_tool_delta(%__MODULE__{} = stream, _json), do: {stream, []}

  @doc """
  No-op for Codex — tool blocks don't accumulate input the way Claude does.
  """
  @spec handle_tool_block_stop(t()) :: {t(), []}
  def handle_tool_block_stop(%__MODULE__{} = stream), do: {stream, []}

  @doc """
  Handle a parsed Codex message. Returns `{updated_stream, events}`.

  Codex messages arrive as complete items (delta: false). This assembler:
  - Replaces the text buffer on each agent_message (not append)
  - Emits rich tool events with command output, exit codes, file changes
  - Tracks thinking/reasoning blocks
  - Handles Codex-specific item types (plan_update, web_search, file_changes)
  """
  @spec handle_message(t(), Message.t()) :: {t(), [event()]}

  # Complete text block — replace buffer, emit replace event
  def handle_message(%__MODULE__{} = stream, %Message{type: :text, content: text, delta: false})
      when is_binary(text) and text != "" do
    {%{stream | buffer: text}, [{:stream_replace, :text, text}]}
  end

  # Text delta (unlikely from Codex, but handle for safety)
  def handle_message(%__MODULE__{} = stream, %Message{type: :text, content: text, delta: true})
      when is_binary(text) do
    new_buffer = stream.buffer <> text
    {%{stream | buffer: new_buffer}, [{:stream_replace, :text, new_buffer}]}
  end

  # Thinking block (complete) — Codex reasoning items
  def handle_message(%__MODULE__{} = stream, %Message{type: :thinking, content: text, delta: false})
      when is_binary(text) and text != "" do
    {stream, [{:stream_replace, :thinking, text}]}
  end

  # Tool use — partial (item.started) shows tool name as in-progress
  def handle_message(
        %__MODULE__{} = stream,
        %Message{type: :tool_use, content: %{name: name, input: input}, metadata: %{partial: true}}
      ) do
    events = [{:stream_delta, :tool_use, name}]

    # For command_execution, also emit the command being run
    events =
      if name == "command_execution" && is_map(input) && input[:command] do
        events ++ [{:stream_tool_input, name, %{command: input[:command]}}]
      else
        events
      end

    {%{stream | tool_name: name}, events}
  end

  # Tool use — complete (item.completed) with rich metadata
  def handle_message(
        %__MODULE__{} = stream,
        %Message{type: :tool_use, content: %{name: name, input: input}}
      ) do
    tool_data = %{name: name, input: input}

    events = [
      {:stream_delta, :tool_use, name},
      {:stream_tool_input, name, input}
    ]

    {%{stream | tool_name: name, last_tool: tool_data}, events}
  end

  # Tool use — name only (string content fallback)
  def handle_message(%__MODULE__{} = stream, %Message{type: :tool_use, content: name})
      when is_binary(name) do
    {%{stream | tool_name: name}, [{:stream_delta, :tool_use, name}]}
  end

  # Catch-all — no events
  def handle_message(%__MODULE__{} = stream, %Message{}) do
    {stream, []}
  end
end
