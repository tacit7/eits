defmodule EyeInTheSky.OrchestratorTimers do
  @moduledoc """
  Public API for orchestrator session timers.

  One active timer per session. Timers outlive the DM page LiveView socket.
  Backed by OrchestratorTimers.Server — callers should never interact with the
  Server directly.
  """

  alias EyeInTheSky.OrchestratorTimers.Server

  @doc "The default message sent when a timer fires."
  def default_message do
    "Please check in with your team members and report their current status and any blockers."
  end

  @min_interval_ms 100

  @doc "Schedule a one-shot timer. Replaces any existing timer for the session."
  def schedule_once(session_id, delay_ms, message \\ default_message()) do
    if is_integer(delay_ms) and delay_ms >= @min_interval_ms do
      GenServer.call(Server, {:schedule_once, session_id, delay_ms, message})
    else
      {:error, {:invalid_interval, "delay_ms must be an integer >= #{@min_interval_ms}, got #{inspect(delay_ms)}"}}
    end
  end

  @doc "Schedule a repeating timer. Replaces any existing timer for the session."
  def schedule_repeating(session_id, interval_ms, message \\ default_message()) do
    if is_integer(interval_ms) and interval_ms >= @min_interval_ms do
      GenServer.call(Server, {:schedule_repeating, session_id, interval_ms, message})
    else
      {:error, {:invalid_interval, "interval_ms must be an integer >= #{@min_interval_ms}, got #{inspect(interval_ms)}"}}
    end
  end

  @doc "Cancel the active timer for a session. No-op if none active."
  def cancel(session_id) do
    GenServer.call(Server, {:cancel, session_id})
  end

  @doc "Return the active timer map for a session, or nil if none active."
  def get_timer(session_id) do
    GenServer.call(Server, {:get_timer, session_id})
  end

  @doc "Return all active timer maps."
  def list_active do
    GenServer.call(Server, :list_active)
  end
end
