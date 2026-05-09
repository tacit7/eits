defmodule EyeInTheSky.Claude.StreamAssemblerDispatcher do
  @moduledoc """
  Dispatcher module for stream assembler operations.

  Replaces protocol dispatch with direct module calls based on struct type,
  eliminating the need for thin wrapper implementations.
  """

  alias EyeInTheSky.Claude.StreamAssembler
  alias EyeInTheSky.Codex.StreamAssembler, as: CodexStreamAssembler

  @doc "Reset all stream state (after SDK completes or errors)."
  def reset(stream) when is_struct(stream, StreamAssembler) do
    StreamAssembler.reset(stream)
  end

  def reset(stream) when is_struct(stream, CodexStreamAssembler) do
    CodexStreamAssembler.reset(stream)
  end

  @doc "Get the current text buffer."
  def buffer(stream) when is_struct(stream, StreamAssembler) do
    StreamAssembler.buffer(stream)
  end

  def buffer(stream) when is_struct(stream, CodexStreamAssembler) do
    CodexStreamAssembler.buffer(stream)
  end

  @doc "Handle a generic SDK message. Returns `{updated_stream, events}`."
  def handle_message(stream, msg) when is_struct(stream, StreamAssembler) do
    StreamAssembler.handle_message(stream, msg)
  end

  def handle_message(stream, msg) when is_struct(stream, CodexStreamAssembler) do
    CodexStreamAssembler.handle_message(stream, msg)
  end

  @doc "Accumulate a tool input JSON delta. Returns `{updated_stream, []}`."
  def handle_tool_delta(stream, json) when is_struct(stream, StreamAssembler) do
    StreamAssembler.handle_tool_delta(stream, json)
  end

  def handle_tool_delta(stream, json) when is_struct(stream, CodexStreamAssembler) do
    CodexStreamAssembler.handle_tool_delta(stream, json)
  end

  @doc "Finalize a completed tool block. Returns `{updated_stream, events}`."
  def handle_tool_block_stop(stream) when is_struct(stream, StreamAssembler) do
    StreamAssembler.handle_tool_block_stop(stream)
  end

  def handle_tool_block_stop(stream) when is_struct(stream, CodexStreamAssembler) do
    CodexStreamAssembler.handle_tool_block_stop(stream)
  end
end
