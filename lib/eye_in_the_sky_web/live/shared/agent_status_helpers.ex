defmodule EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers do
  @moduledoc """
  Shared helpers for handling agent status changes across LiveViews.

  All `:agent_working` and `:agent_stopped` PubSub messages carry a single
  `%Session{}` struct as payload. Use these helpers to extract the session ID
  and dispatch callbacks uniformly.
  """

  @doc """
  Extracts session_id from an agent status message (a Session struct).

  Returns nil if the message is not a recognized struct.
  """
  def extract_session_id(%{id: session_id}), do: session_id
  def extract_session_id(_), do: nil

  @doc """
  Helper to handle agent_working events with a callback.

  The callback receives (socket, session_id) and should return the updated socket.

  ## Example

      def handle_info({:agent_working, msg}, socket) do
        AgentStatusHelpers.handle_agent_working(socket, msg, fn socket, session_id ->
          update(socket, :working_agents, &Map.put(&1, session_id, true))
        end)
      end
  """
  def handle_agent_working(socket, msg, callback) when is_function(callback, 2) do
    session_id = extract_session_id(msg)
    {:noreply, callback.(socket, session_id)}
  end

  @doc """
  Helper to handle agent_stopped events with a callback.

  The callback receives (socket, session_id) and should return the updated socket.

  ## Example

      def handle_info({:agent_stopped, msg}, socket) do
        AgentStatusHelpers.handle_agent_stopped(socket, msg, fn socket, session_id ->
          update(socket, :working_agents, &Map.delete(&1, session_id))
        end)
      end
  """
  def handle_agent_stopped(socket, msg, callback) when is_function(callback, 2) do
    session_id = extract_session_id(msg)
    {:noreply, callback.(socket, session_id)}
  end

  @doc """
  Conditional handler for agent_working that only processes if session_id matches.

  Used in LiveViews that track a single session (like dm_live).

  ## Example

      def handle_info({:agent_working, msg}, socket) do
        AgentStatusHelpers.handle_agent_working_if_match(
          socket, msg, :session_id,
          fn socket, _session_id -> assign(socket, :processing, true) end
        )
      end
  """
  def handle_agent_working_if_match(socket, msg, session_assign_key, callback) when is_function(callback, 2) do
    session_id = extract_session_id(msg)
    current_session = socket.assigns[session_assign_key]

    if session_id == current_session do
      {:noreply, callback.(socket, session_id)}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Conditional handler for agent_stopped that only processes if session_id matches.

  Used in LiveViews that track a single session (like dm_live).

  ## Example

      def handle_info({:agent_stopped, msg}, socket) do
        AgentStatusHelpers.handle_agent_stopped_if_match(
          socket, msg, :session_id,
          fn socket, _session_id -> assign(socket, :processing, false) end
        )
      end
  """
  def handle_agent_stopped_if_match(socket, msg, session_assign_key, callback) when is_function(callback, 2) do
    session_id = extract_session_id(msg)
    current_session = socket.assigns[session_assign_key]

    if session_id == current_session do
      {:noreply, callback.(socket, session_id)}
    else
      {:noreply, socket}
    end
  end
end
