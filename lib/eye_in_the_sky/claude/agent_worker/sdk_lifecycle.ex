defmodule EyeInTheSky.Claude.AgentWorker.SdkLifecycle do
  @moduledoc """
  Manages the SDK process lifecycle for AgentWorker.

  Handles starting, monitoring, retrying, and cancelling SDK processes.
  All functions take AgentWorker state and return updated state or tagged
  result tuples — the GenServer boundary stays in AgentWorker.
  """

  require Logger

  alias EyeInTheSky.AgentWorkerEvents, as: WorkerEvents
  alias EyeInTheSky.Claude.AgentWorker.WatchdogTimer
  alias EyeInTheSky.Claude.ProviderStrategy

  @doc """
  Starts the SDK for the given job. Selects start vs resume based on
  job.context[:has_messages]. Returns `{:ok, sdk_ref, monitor_ref, handler_pid}`
  or `{:error, reason}`.
  """
  def start_sdk(%{} = state, job) do
    strategy = ProviderStrategy.for_provider(state.provider)
    has_messages = job.context[:has_messages] || false

    result =
      if has_messages do
        strategy.resume(state, job)
      else
        strategy.start(state, job)
      end

    monitor_handler(result)
  end

  @doc """
  Attempts to restart the SDK with a new job after an error.

  Returns:
    - `{:ok, new_state}` — SDK started successfully; state updated with new refs
    - `{:start_next, clean_state}` — SDK start failed; caller should process the next queued job
  """
  def attempt_sdk_retry(state, new_job, log_label, opts \\ []) do
    broadcast_started = Keyword.get(opts, :broadcast_started, false)

    case start_sdk(state, new_job) do
      {:ok, sdk_ref, handler_monitor, handler_pid} ->
        if broadcast_started,
          do: WorkerEvents.on_sdk_started(state.session_id, state.provider_conversation_id)

        demonitor_handler(state.handler_monitor)

        new_state =
          %{
            state
            | sdk_ref: sdk_ref,
              handler_monitor: handler_monitor,
              handler_pid: handler_pid,
              current_job: new_job
          }
          |> WatchdogTimer.schedule_watchdog()

        {:ok, new_state}

      {:error, start_reason} ->
        Logger.error("[#{state.session_id}] #{log_label}: #{inspect(start_reason)}")
        WorkerEvents.on_sdk_errored(state.session_id, state.provider_conversation_id)
        demonitor_handler(state.handler_monitor)

        clean_state = %{
          state
          | status: :idle,
            sdk_ref: nil,
            handler_monitor: nil,
            current_job: nil
        }

        {:start_next, clean_state}
    end
  end

  @doc "Cancels the active SDK process. No-op if no SDK is running."
  def cancel_active_sdk(%{sdk_ref: nil}), do: :ok

  def cancel_active_sdk(%{sdk_ref: ref, provider: provider}) do
    strategy = ProviderStrategy.for_provider(provider || "claude")
    strategy.cancel(ref)
  end

  @doc "Removes the process monitor for the handler process."
  def demonitor_handler(nil), do: :ok
  def demonitor_handler(ref), do: Process.demonitor(ref, [:flush])

  # Convert {:ok, sdk_ref, handler_pid} to {:ok, sdk_ref, monitor_ref, handler_pid}
  defp monitor_handler({:ok, sdk_ref, handler_pid}) do
    monitor_ref = Process.monitor(handler_pid)
    {:ok, sdk_ref, monitor_ref, handler_pid}
  end

  defp monitor_handler({:error, _} = error), do: error
end
