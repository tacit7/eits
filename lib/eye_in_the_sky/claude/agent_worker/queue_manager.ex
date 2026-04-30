defmodule EyeInTheSky.Claude.AgentWorker.QueueManager do
  @moduledoc """
  Manages the AgentWorker message queue: admission control, job enqueueing,
  and dispatching the next queued job when the worker becomes idle.

  All functions take AgentWorker state and return updated state or a
  {reply, state} tuple. The GenServer boundary stays in AgentWorker.
  """

  require Logger

  alias EyeInTheSky.AgentWorkerEvents, as: WorkerEvents
  alias EyeInTheSky.Claude.AgentWorker.{IdleTimer, Reconciliation, RetryPolicy, SdkLifecycle, WatchdogTimer}
  alias EyeInTheSky.Claude.Job
  alias EyeInTheSky.Messages

  @max_queue_depth 5

  @doc """
  Appends a job to the queue (assigning an ID first) and broadcasts the update.
  Returns the updated state.
  """
  def enqueue_job(state, %Job{} = job) do
    job = Job.assign_id(job)
    new_queue = state.queue ++ [job]
    new_state = %{state | queue: new_queue}
    WorkerEvents.broadcast_queue_update(state.session_id, new_queue)
    new_state
  end

  @doc """
  Processes the next job from the queue when the worker becomes idle.

  If the queue is empty, broadcasts a queue-cleared update and returns state
  unchanged. If a job is available, starts the SDK. On SDK start failure,
  schedules a retry.

  Returns updated state (caller is responsible for wrapping in `{:noreply, ...}`).
  """
  def process_next_job(%{queue: []} = state) do
    WorkerEvents.broadcast_queue_update(state.session_id, state.queue)
    state
  end

  def process_next_job(%{queue: [next_job | rest]} = state) do
    # Re-evaluate has_messages at dequeue time — the prior job may have produced a reply
    # since this job was submitted, making the stale value wrong (false → start instead of resume).
    fresh_has_messages = Messages.has_inbound_reply?(state.session_id, state.provider)
    next_job = put_in(next_job.context[:has_messages], fresh_has_messages)

    case SdkLifecycle.start_sdk(state, next_job) do
      {:ok, sdk_ref, handler_monitor, handler_pid} ->
        WorkerEvents.on_sdk_started(state.session_id, state.provider_conversation_id)
        Messages.mark_processing(next_job.context[:message_id])

        new_state =
          %{
            state
            | status: :running,
              sdk_ref: sdk_ref,
              handler_monitor: handler_monitor,
              handler_pid: handler_pid,
              current_job: next_job,
              queue: rest
          }
          |> RetryPolicy.clear_retry_timer()
          |> WatchdogTimer.schedule_watchdog()

        WorkerEvents.broadcast_queue_update(state.session_id, new_state.queue)
        new_state

      {:error, reason} ->
        Logger.error("Failed to start SDK for next job: #{inspect(reason)}")
        RetryPolicy.schedule_retry_start(%{state | queue: [next_job | rest]})
    end
  end

  @doc """
  Handles job admission when the worker is idle: starts the SDK immediately.
  Returns `{{:ok, :started}, new_state}` or `{{:ok, :retry_queued}, retry_state}`.
  """
  def admit_idle(state, job) do
    Logger.info("AgentWorker: starting SDK for session_id=#{state.session_id}")

    case SdkLifecycle.start_sdk(state, job) do
      {:ok, sdk_ref, handler_monitor, handler_pid} ->
        Logger.info("AgentWorker: SDK started for session_id=#{state.session_id}")

        :telemetry.execute(
          [:eits, :agent, :job, :started],
          %{system_time: System.system_time()},
          %{session_id: state.session_id}
        )

        WorkerEvents.on_sdk_started(state.session_id, state.provider_conversation_id)
        Messages.mark_processing(job.context[:message_id])

        new_state =
          %{
            state
            | status: :running,
              sdk_ref: sdk_ref,
              handler_monitor: handler_monitor,
              handler_pid: handler_pid,
              current_job: job
          }
          |> RetryPolicy.clear_retry_timer()
          |> WatchdogTimer.schedule_watchdog()

        {{:ok, :started}, new_state}

      {:error, reason} ->
        reason_str = inspect(reason)

        Logger.error(
          "AgentWorker: failed to start SDK for session_id=#{state.session_id} - #{reason_str}"
        )

        WorkerEvents.on_spawn_error(state.session_id, reason)

        {{:ok, :retry_queued}, state |> enqueue_job(job) |> RetryPolicy.schedule_retry_start()}
    end
  end

  @doc """
  Handles the full submit_message logic. Recovers from :failed state, logs,
  emits telemetry, creates a Job, then delegates to `admit_idle/2` or `admit_busy/2`.

  Returns `{reply_term, new_state}`. Context must already be normalized via
  `Job.normalize_context/1` before calling.
  """
  def submit(message, context, %{status: :failed} = state) do
    Logger.info("AgentWorker: recovering from :failed state for session_id=#{state.session_id}")
    submit(message, context, %{state | status: :idle, retry_attempt: 0})
  end

  def submit(message, context, state) do
    metadata_note =
      if context[:dm_metadata] && context[:dm_metadata] != %{} do
        ", using_metadata=true"
      else
        ""
      end

    Logger.info(
      "AgentWorker.submit_message: session_id=#{state.session_id}, " <>
        "message_length=#{String.length(message)}, has_messages=#{context.has_messages}, " <>
        "model=#{inspect(context.model)}#{metadata_note}"
    )

    state = IdleTimer.cancel(state)
    queue_len = length(state.queue)

    Reconciliation.emit(
      [:eits, :agent, :job, :received],
      %{system_time: System.system_time()},
      %{queue_length: queue_len, has_messages: context.has_messages},
      state
    )

    job = Job.new(message, context, context[:content_blocks] || [])

    if state.status == :idle do
      case admit_idle(state, job) do
        {{:ok, :started}, new_state} ->
          {{:ok, :started}, Reconciliation.start_job_trace(new_state)}

        other ->
          other
      end
    else
      admit_busy(state, job)
    end
  end

  @doc """
  Handles job admission when the worker is busy: queues the job or rejects it
  if the queue is full.
  Returns `{{:error, :queue_full}, state}` or `{{:ok, :queued}, new_state}`.
  """
  def admit_busy(state, job) do
    if length(state.queue) >= @max_queue_depth do
      Logger.warning(
        "AgentWorker: queue full (#{@max_queue_depth}) for session_id=#{state.session_id}, rejecting message"
      )

      {{:error, :queue_full}, state}
    else
      new_queue_length = length(state.queue) + 1

      Logger.info(
        "AgentWorker: busy, queueing message for session_id=#{state.session_id}, " <>
          "queue_length=#{new_queue_length}"
      )

      :telemetry.execute(
        [:eits, :agent, :job, :queued],
        %{queue_length: new_queue_length},
        %{session_id: state.session_id}
      )

      {{:ok, :queued}, enqueue_job(state, job)}
    end
  end
end
