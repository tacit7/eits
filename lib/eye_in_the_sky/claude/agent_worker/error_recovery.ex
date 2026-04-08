defmodule EyeInTheSky.Claude.AgentWorker.ErrorRecovery do
  @moduledoc """
  SDK error recovery handlers extracted from AgentWorker handle_info clauses.

  Each function accepts a state struct and returns `{:noreply, new_state}`, making
  them unit-testable without spinning up a GenServer.
  """

  require Logger

  alias EyeInTheSky.AgentWorkerEvents, as: WorkerEvents
  alias EyeInTheSky.Claude.AgentWorker.{ErrorClassifier, ProcessCleanup, QueueManager, SdkLifecycle, WatchdogTimer}
  alias EyeInTheSky.Claude.{Job, StreamAssemblerProtocol}
  alias EyeInTheSky.Messages

  @doc """
  Handles a stale Claude session error (`No conversation found`).
  Retries the current job as a fresh session when applicable; falls back to
  generic error handling otherwise.
  """
  def handle_stale_session({:claude_result_error, %{errors: errors}} = reason, state) do
    WorkerEvents.broadcast_stream_clear(state.session_id)
    state = %{state | stream: StreamAssemblerProtocol.reset(state.stream)}
    job = state.current_job

    if Enum.any?(errors, &String.contains?(&1, "No conversation found")) && not is_nil(job) do
      Logger.warning(
        "[#{state.session_id}] Stale Claude session UUID=#{state.provider_conversation_id}, retrying as new session"
      )

      dispatch_sdk_retry(state, Job.as_fresh_session(job), "Failed to restart fresh SDK")
    else
      do_handle_sdk_error(reason, state)
    end
  end

  @doc """
  Handles a session-already-in-use error.
  Kills any orphaned Claude process holding the session lock, then retries as resume
  exactly once. The `:kill_retry` flag in the job context prevents a second kill attempt.
  """
  def handle_session_in_use({:cli_error, msg} = reason, state) do
    WorkerEvents.broadcast_stream_clear(state.session_id)
    state = %{state | stream: StreamAssemblerProtocol.reset(state.stream)}
    job = state.current_job

    already_retried = Map.get(job.context, :kill_retry, false)

    if String.contains?(msg, "already in use") && not is_nil(job) && not already_retried do
      uuid = state.provider_conversation_id

      Logger.warning(
        "[#{state.session_id}] Session UUID=#{uuid} already in use — killing orphan and retrying as resume"
      )

      ProcessCleanup.kill_orphaned(uuid)

      resume_job = Job.as_resume(job)
      resume_job = %{resume_job | context: Map.put(resume_job.context, :kill_retry, true)}

      dispatch_sdk_retry(state, resume_job, "Failed to resume after already-in-use",
        broadcast_started: true
      )
    else
      do_handle_sdk_error(reason, state)
    end
  end

  @doc """
  Handles a generic SDK error: clears stream and delegates to error classification.
  """
  def handle_generic_error(reason, state) do
    WorkerEvents.broadcast_stream_clear(state.session_id)
    do_handle_sdk_error(reason, %{state | stream: StreamAssemblerProtocol.reset(state.stream)})
  end

  @doc """
  Core SDK error handler: logs, emits telemetry, cancels the SDK process, then routes
  to systemic or transient recovery based on `ErrorClassifier.systemic?/1`.

  Called directly by watchdog and handler-crash paths in addition to the three
  error recovery entry points above.
  """
  def do_handle_sdk_error(reason, state) do
    Logger.error("[#{state.session_id}] SDK error: #{inspect(reason)}")

    :telemetry.execute(
      [:eits, :agent, :sdk, :error],
      %{system_time: System.system_time()},
      %{reason: reason, session_id: state.session_id}
    )

    state = WatchdogTimer.cancel_watchdog(state)
    SdkLifecycle.cancel_active_sdk(state)
    WorkerEvents.on_sdk_errored(state.session_id, state.provider_conversation_id)
    SdkLifecycle.demonitor_handler(state.handler_monitor)

    state = %{state | handler_pid: nil, sdk_ref: nil, handler_monitor: nil}

    if ErrorClassifier.systemic?(reason) do
      handle_systemic_error(state, reason)
    else
      handle_transient_error(state)
    end
  end

  # --- Private ---

  defp handle_systemic_error(state, reason) do
    WorkerEvents.on_current_job_failed(state.current_job, reason)

    WorkerEvents.on_queue_drained(
      state.session_id,
      state.provider_conversation_id,
      state.queue,
      reason
    )

    WorkerEvents.broadcast_queue_update(state.session_id, [])

    {:noreply,
     %{state | status: :failed, sdk_ref: nil, handler_monitor: nil, current_job: nil, queue: []}}
  end

  defp handle_transient_error(state) do
    if state.current_job do
      Messages.mark_failed(state.current_job.context[:message_id], "transient_error")
    end

    {:noreply,
     QueueManager.process_next_job(%{
       state
       | status: :idle,
         sdk_ref: nil,
         handler_monitor: nil,
         current_job: nil
     })}
  end

  defp dispatch_sdk_retry(state, job, label, opts \\ []) do
    case SdkLifecycle.attempt_sdk_retry(state, job, label, opts) do
      {:ok, new_state} -> {:noreply, new_state}
      {:start_next, clean_state} -> {:noreply, QueueManager.process_next_job(clean_state)}
    end
  end
end
