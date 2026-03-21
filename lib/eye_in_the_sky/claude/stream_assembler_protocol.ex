defprotocol EyeInTheSky.Claude.StreamAssemblerProtocol do
  @moduledoc """
  Protocol for stream assembler implementations.

  Both Claude and Codex stream assemblers implement this interface so
  AgentWorker can dispatch without branching on provider type.

  Implementors: `EyeInTheSky.Claude.StreamAssembler`,
                `EyeInTheSky.Codex.StreamAssembler`
  """

  @doc "Reset all stream state (after SDK completes or errors)."
  def reset(stream)

  @doc "Get the current text buffer."
  def buffer(stream)

  @doc "Handle a generic SDK message. Returns `{updated_stream, events}`."
  def handle_message(stream, msg)

  @doc "Accumulate a tool input JSON delta. Returns `{updated_stream, []}`."
  def handle_tool_delta(stream, json)

  @doc "Finalize a completed tool block. Returns `{updated_stream, events}`."
  def handle_tool_block_stop(stream)
end

defimpl EyeInTheSky.Claude.StreamAssemblerProtocol,
  for: EyeInTheSky.Claude.StreamAssembler do
  alias EyeInTheSky.Claude.StreamAssembler

  def reset(s), do: StreamAssembler.reset(s)
  def buffer(s), do: StreamAssembler.buffer(s)
  def handle_message(s, msg), do: StreamAssembler.handle_message(s, msg)
  def handle_tool_delta(s, json), do: StreamAssembler.handle_tool_delta(s, json)
  def handle_tool_block_stop(s), do: StreamAssembler.handle_tool_block_stop(s)
end

defimpl EyeInTheSky.Claude.StreamAssemblerProtocol,
  for: EyeInTheSky.Codex.StreamAssembler do
  alias EyeInTheSky.Codex.StreamAssembler, as: CodexStreamAssembler

  def reset(s), do: CodexStreamAssembler.reset(s)
  def buffer(s), do: CodexStreamAssembler.buffer(s)
  def handle_message(s, msg), do: CodexStreamAssembler.handle_message(s, msg)
  def handle_tool_delta(s, json), do: CodexStreamAssembler.handle_tool_delta(s, json)
  def handle_tool_block_stop(s), do: CodexStreamAssembler.handle_tool_block_stop(s)
end
