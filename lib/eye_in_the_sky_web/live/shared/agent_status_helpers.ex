defmodule EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers do
  @moduledoc """
  Shared helpers for agent status updates in LiveViews.
  """

  @doc "Update agent status if session ID matches, set last_activity_at if status is not 'idle'"
  def apply_agent_status(agent, session_id, new_status, now) do
    if agent.id == session_id do
      agent = %{agent | status: new_status}
      if new_status == "idle", do: %{agent | last_activity_at: now}, else: agent
    else
      agent
    end
  end

  def handle_agent_working(socket, msg, callback) do
    session_id = get_in(msg, [:session, :id])
    if session_id, do: {:noreply, callback.(socket, session_id)}, else: {:noreply, socket}
  end

  def handle_agent_stopped(socket, msg, callback) do
    session_id = get_in(msg, [:session, :id])
    if session_id, do: {:noreply, callback.(socket, session_id)}, else: {:noreply, socket}
  end

  def handle_agent_working_if_match(socket, msg, key, callback) do
    value = get_in(msg, [key])
    if value == get_in(socket.assigns, [key]) do
      {:noreply, callback.(socket, value)}
    else
      {:noreply, socket}
    end
  end

  def handle_agent_stopped_if_match(socket, msg, key, callback) do
    value = get_in(msg, [key])
    if value == get_in(socket.assigns, [key]) do
      {:noreply, callback.(socket, value)}
    else
      {:noreply, socket}
    end
  end
end
