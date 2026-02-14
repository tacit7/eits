defmodule EyeInTheSkyWeb.Claude.Message do
  @moduledoc """
  Represents a parsed message from Claude's stream-json output.

  Messages can be text content, tool uses, thinking blocks, usage stats, or errors.
  """

  @type message_type :: :text | :tool_use | :tool_result | :thinking | :usage | :error | :session_start

  @type t :: %__MODULE__{
          type: message_type(),
          content: String.t() | map(),
          delta: boolean(),
          metadata: map()
        }

  defstruct [:type, :content, delta: false, metadata: %{}]

  @doc """
  Create a text message.
  """
  def text(content, delta \\ false) do
    %__MODULE__{type: :text, content: content, delta: delta}
  end

  @doc """
  Create a tool use message.
  """
  def tool_use(name, input, metadata \\ %{}) do
    %__MODULE__{
      type: :tool_use,
      content: %{name: name, input: input},
      metadata: metadata
    }
  end

  @doc """
  Create a thinking message.
  """
  def thinking(content, delta \\ false) do
    %__MODULE__{type: :thinking, content: content, delta: delta}
  end

  @doc """
  Create a usage message.
  """
  def usage(input_tokens, output_tokens) do
    %__MODULE__{
      type: :usage,
      content: %{input_tokens: input_tokens, output_tokens: output_tokens}
    }
  end

  @doc """
  Create an error message.
  """
  def error(reason, metadata \\ %{}) do
    %__MODULE__{type: :error, content: reason, metadata: metadata}
  end

  @doc """
  Create a session start message with session_id.
  """
  def session_start(session_id) do
    %__MODULE__{type: :session_start, content: session_id}
  end
end
