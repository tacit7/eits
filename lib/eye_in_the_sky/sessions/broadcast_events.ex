defmodule EyeInTheSky.Sessions.BroadcastEvents do
  @moduledoc false

  alias EyeInTheSky.Events

  def broadcast_session_updated(session), do: Events.session_updated(session)

  def broadcast_session_completed(session),
    do: broadcast_with_session_updated(session, &Events.session_completed/1)

  def broadcast_session_waiting(session),
    do: broadcast_with_session_updated(session, &Events.agent_stopped/1)

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
