defmodule EyeInTheSkyWebWeb.Live.Shared.AgentStatusHelpers do
  @moduledoc """
  Shared helpers for handling agent status changes across LiveViews.

  Provides helper functions that extract session IDs from both map and 3-tuple
  message formats for `:agent_working` and `:agent_stopped` events.
  """

  @doc """
  Extracts session_id from agent status messages.

  Handles both message formats:
  - Map form: `%{id: session_id, ...}` → returns session_id
  - Tuple form: `session_id` (3rd element already extracted) → returns session_id

  Returns nil if format is not recognized.
  """
  def extract_session_id(%{id: session_id}), do: session_id
  def extract_session_id(session_id) when is_integer(session_id), do: session_id
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
