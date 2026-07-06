defmodule EyeInTheSky.Sessions.Events do
  @moduledoc """
  PubSub event broadcasting for sessions.
  """

  alias EyeInTheSky.Desktop
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

      maybe_alert_desktop(session, status)
    end

    Events.session_updated(session)
  end

  # High-urgency desktop escalation for the states that need a human now:
  # a crashed session (`failed`) or a spawned agent that finished and awaits
  # resume/input (`waiting`). Normal transitions (completed/idle) stay quiet —
  # the dock badge already reflects them. No-op outside the desktop shell.
  defp maybe_alert_desktop(session, status) do
    case desktop_alert_spec(session, status) do
      {title, body, path} -> Desktop.alert(title, body, path)
      nil -> :ok
    end
  end

  @doc """
  Pure mapping of a session status to a desktop alert `{title, body, path}`,
  or `nil` when the status does not warrant escalation. Exposed for testing.
  """
  def desktop_alert_spec(session, "failed"),
    do: {"Session failed", alert_body(session), session_path(session)}

  def desktop_alert_spec(session, "waiting"),
    do: {"Waiting for input", alert_body(session), session_path(session)}

  def desktop_alert_spec(_session, _status), do: nil

  defp alert_body(session) do
    name = session.name || "Agent"

    case Map.get(session, :status_reason) do
      reason when is_binary(reason) and reason != "" -> "#{name} — #{reason}"
      _ -> name
    end
  end

  defp session_path(%{uuid: uuid}) when is_binary(uuid), do: "/dm/#{uuid}"
  defp session_path(_), do: nil

  defp broadcast_with_session_updated(session, event_fn) do
    event_fn.(session)
    Events.session_updated(session)
  end
end
