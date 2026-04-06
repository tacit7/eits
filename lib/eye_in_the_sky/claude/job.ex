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
          content_blocks: [EyeInTheSky.Claude.ContentBlock.t()],
          submitted_at: DateTime.t()
        }

  @enforce_keys [:message, :context]
  defstruct [
    :id,
    :message,
    :context,
    content_blocks: [],
    submitted_at: nil
  ]

  @doc """
  Create a new Job from a message and context.
  """
  def new(message, context) when is_binary(message) and is_map(context) do
    %__MODULE__{
      message: message,
      context: context,
      content_blocks: [],
      submitted_at: DateTime.utc_now()
    }
  end

  @doc """
  Create a new Job from a message, context, and content blocks.
  """
  def new(message, context, content_blocks)
      when is_binary(message) and is_map(context) and is_list(content_blocks) do
    %__MODULE__{
      message: message,
      context: context,
      content_blocks: content_blocks,
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

  @doc """
  Return a copy of this job with has_messages set to true (force resume).
  Used when Claude rejects a start because the session ID already exists on disk.
  """
  def as_resume(%__MODULE__{} = job) do
    %{job | context: %{job.context | has_messages: true}}
  end

  @doc """
  Normalize a raw context value into a well-typed map suitable for job creation.

  Accepts a keyword list, any non-map value (treated as empty), or a map.
  All three clauses must be kept together.
  """
  def normalize_context(context) when is_list(context), do: normalize_context(Map.new(context))
  def normalize_context(context) when not is_map(context), do: normalize_context(%{})

  def normalize_context(context) do
    %{
      model: Map.get(context, :model),
      effort_level: Map.get(context, :effort_level),
      has_messages: Map.get(context, :has_messages, false),
      channel_id: Map.get(context, :channel_id),
      thinking_budget: Map.get(context, :thinking_budget),
      max_budget_usd: Map.get(context, :max_budget_usd),
      agent: Map.get(context, :agent),
      eits_workflow: Map.get(context, :eits_workflow, "1"),
      bypass_sandbox: Map.get(context, :bypass_sandbox, false),
      content_blocks: Map.get(context, :content_blocks, []),
      message_id: Map.get(context, :message_id),
      extra_cli_opts: Map.get(context, :extra_cli_opts, []),
      kill_retry: Map.get(context, :kill_retry, false)
    }
  end
end
