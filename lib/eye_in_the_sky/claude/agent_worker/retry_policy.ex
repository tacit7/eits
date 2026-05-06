defmodule EyeInTheSky.Claude.AgentWorker.RetryPolicy do
  @moduledoc """
  Manages exponential-backoff retry scheduling for AgentWorker.

  Retry attempts use exponential backoff capped at `@retry_max_ms`.
  After `@max_retries` attempts the worker transitions to `:failed`.
  """

  require Logger

  alias EyeInTheSky.AgentWorkerEvents, as: WorkerEvents

  @retry_start_ms 1_000
  @retry_max_ms 30_000
  @max_retries 5

  @doc "Exposed for tests."
  def max_retries, do: @max_retries

  @doc """
  Schedules a `:retry_start` message after an exponential delay, or marks
  the worker as `:failed` when max retries are exhausted.

  Returns the updated state.
  """
  def schedule_retry_start(%{retry_timer_ref: nil, retry_attempt: attempt} = state)
      when attempt >= @max_retries do
    Logger.error("[#{state.session_id}] Max retries (#{@max_retries}) exceeded, giving up")

    # Mark all queued messages failed before clearing — DB must reflect loss before memory is cleared.
    WorkerEvents.on_queue_drained(state, :retry_exhausted)

    WorkerEvents.on_max_retries_exceeded(
      state.session_id,
      state.provider_conversation_id,
      :retry_exhausted
    )

    WorkerEvents.broadcast_queue_update(state.session_id, [])

    %{state | status: :failed, queue: [], retry_attempt: 0}
  end

  def schedule_retry_start(%{retry_timer_ref: nil} = state) do
    delay = min(round(@retry_start_ms * :math.pow(2, state.retry_attempt)), @retry_max_ms)

    Logger.info(
      "[#{state.session_id}] Scheduling retry in #{delay}ms (attempt=#{state.retry_attempt})"
    )

    timer_ref = Process.send_after(self(), :retry_start, delay)

    %{
      state
      | status: :retry_wait,
        retry_timer_ref: timer_ref,
        retry_attempt: state.retry_attempt + 1
    }
  end

  # Timer already set — nothing to do.
  def schedule_retry_start(state), do: state

  @doc """
  Cancels the pending retry timer and resets the attempt counter.

  Returns the updated state.
  """
  def clear_retry_timer(%{retry_timer_ref: nil} = state), do: %{state | retry_attempt: 0}

  def clear_retry_timer(state) do
    Process.cancel_timer(state.retry_timer_ref)
    %{state | retry_timer_ref: nil, retry_attempt: 0}
  end
end
