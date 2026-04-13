defmodule EyeInTheSky.Claude.AgentWorker.IdleTimer do
  @moduledoc """
  Idle timeout helpers for AgentWorker.

  Workers schedule a timer whenever they become idle with an empty queue.
  If no new job arrives within @idle_timeout_ms, the worker stops itself
  (`:normal` exit, not restarted due to `restart: :transient`), freeing
  the AgentSupervisor slot.
  """

  @idle_timeout_ms :timer.minutes(30)

  @doc "Schedule (or reschedule) the idle timeout. Cancels any existing timer first."
  def schedule(state) do
    state = cancel(state)
    ref = Process.send_after(self(), :idle_timeout, @idle_timeout_ms)
    %{state | idle_timer_ref: ref}
  end

  @doc "Cancel the idle timer if one is running."
  def cancel(%{idle_timer_ref: nil} = state), do: state

  def cancel(%{idle_timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | idle_timer_ref: nil}
  end

  @doc "Schedule idle timer only when status is :idle and queue is empty."
  def maybe_schedule(%{status: :idle, queue: []} = state), do: schedule(state)
  def maybe_schedule(state), do: state

  def idle_timeout_ms, do: @idle_timeout_ms
end
