defmodule EyeInTheSky.Sessions.Events do
  @moduledoc """
  PubSub event broadcasting for sessions.
  """

  alias EyeInTheSky.Events

  @doc "Broadcasts a session_updated event."
  def broadcast_session_updated(session), do: Events.session_updated(session)

  @doc "Broadcasts a session_completed event."
  def broadcast_session_completed(session),
    do: broadcast_with_session_updated(session, &Events.session_completed/1)

  @doc "Broadcasts a session_waiting event."
  def broadcast_session_waiting(session),
    do: broadcast_with_session_updated(session, &Events.agent_stopped/1)

  @doc "Broadcasts status-specific side effects for a session."
  def broadcast_status_side_effects(session, status) do
    if status do
      if status in ["completed", "failed", "waiting", "idle"] do
        Events.agent_stopped(session)
      else
        Events.agent_working(session)
      end
    end

    Events.session_updated(session)
  end

  defp broadcast_with_session_updated(session, event_fn) do
    event_fn.(session)
    Events.session_updated(session)
  end
end
