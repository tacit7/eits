defmodule EyeInTheSky.Claude.StreamAssemblerBehavior do
  @moduledoc """
  Behavior defining the StreamAssembler interface.

  Both Claude and Codex stream assemblers implement this behavior,
  providing a unified interface for AgentWorker to dispatch stream
  operations without branching on provider type.

  Implementors: `EyeInTheSky.Claude.StreamAssembler`,
                `EyeInTheSky.Codex.StreamAssembler`
  """

  @doc "Reset all stream state (after SDK completes or errors)."
  @callback reset(stream :: any()) :: any()

  @doc "Get the current text buffer."
  @callback buffer(stream :: any()) :: String.t()

  @doc "Handle a generic SDK message. Returns `{updated_stream, events}`."
  @callback handle_message(stream :: any(), msg :: any()) :: {any(), list()}

  @doc "Accumulate a tool input JSON delta. Returns `{updated_stream, []}`."
  @callback handle_tool_delta(stream :: any(), json :: String.t()) :: {any(), list()}

  @doc "Finalize a completed tool block. Returns `{updated_stream, events}`."
  @callback handle_tool_block_stop(stream :: any()) :: {any(), list()}
end
