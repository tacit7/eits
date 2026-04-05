defmodule EyeInTheSky.Claude.AgentWorker.WatchdogTimer do
  @moduledoc """
  Manages the watchdog timer that detects stuck AgentWorker processes.

  The watchdog fires after a configurable timeout. If the handler process is
  still alive, the watchdog rearms for the same run_ref. If the handler is
  dead, the worker is considered stuck and error recovery is triggered.
  """

  @doc "Returns the configured watchdog timeout in milliseconds."
  def watchdog_timeout_ms do
    Application.get_env(:eye_in_the_sky, :watchdog_timeout_ms, 10 * 60 * 1_000)
  end

  @doc """
  Arms the watchdog for a new SDK run. Cancels any existing timer first.
  Returns updated state with :watchdog_timer_ref and :watchdog_run_ref set.
  """
  def schedule_watchdog(state) do
    state = cancel_watchdog(state)
    run_ref = make_ref()
    timeout = watchdog_timeout_ms()
    timer_ref = Process.send_after(self(), {:watchdog_check, run_ref}, timeout)
    %{state | watchdog_timer_ref: timer_ref, watchdog_run_ref: run_ref}
  end

  @doc """
  Cancels the active watchdog timer.
  Returns updated state with :watchdog_timer_ref and :watchdog_run_ref cleared.
  """
  def cancel_watchdog(%{watchdog_timer_ref: nil} = state) do
    %{state | watchdog_run_ref: nil}
  end

  def cancel_watchdog(%{watchdog_timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | watchdog_timer_ref: nil, watchdog_run_ref: nil}
  end

  @doc """
  Rearms the watchdog for the same run_ref (used when the handler is still alive
  on a slow run). Returns updated state with a new :watchdog_timer_ref.
  """
  def rearm(state, run_ref) do
    timeout = watchdog_timeout_ms()
    new_timer_ref = Process.send_after(self(), {:watchdog_check, run_ref}, timeout)
    %{state | watchdog_timer_ref: new_timer_ref}
  end
end
