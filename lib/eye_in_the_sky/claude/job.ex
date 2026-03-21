defmodule EyeInTheSky.Claude.Job do
  @moduledoc """
  Represents a queued or in-flight job for the AgentWorker.

  Every message submitted to the worker becomes a Job with a unique ID,
  the message payload, normalized context, and submission timestamp.
  """

  @type t :: %__MODULE__{
          id: integer() | nil,
          message: String.t(),
          context: map(),
          submitted_at: DateTime.t()
        }

  @enforce_keys [:message, :context]
  defstruct [
    :id,
    :message,
    :context,
    submitted_at: nil
  ]

  @doc """
  Create a new Job from a message and context.
  """
  def new(message, context) when is_binary(message) and is_map(context) do
    %__MODULE__{
      message: message,
      context: context,
      submitted_at: DateTime.utc_now()
    }
  end

  @doc """
  Assign a unique monotonic ID to this job (for queue identity).
  """
  def assign_id(%__MODULE__{} = job) do
    %{job | id: System.unique_integer([:positive, :monotonic])}
  end

  @doc """
  Return a copy of this job with has_messages set to false (for fresh session retry).
  """
  def as_fresh_session(%__MODULE__{} = job) do
    %{job | context: %{job.context | has_messages: false}}
  end
end
