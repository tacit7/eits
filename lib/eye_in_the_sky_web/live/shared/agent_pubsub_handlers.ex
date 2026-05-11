defmodule EyeInTheSkyWeb.Live.Shared.AgentPubSubHandlers do
  @moduledoc """
  Shared handlers for agent_working and agent_stopped PubSub events.

  Provides unified implementations for updating agent status across LiveViews
  that maintain a list or stream of agents.

  This module delegates to AgentStatusHelpers for the core status update logic
  and provides convenient wrapper functions that eliminate boilerplate.
  """

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.Helpers.SessionFilters
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers

  @doc """
  Generic handle_info for :agent_working events that updates a list of agents.

  Used by LiveViews that maintain agents in a simple list (e.g., AgentLive.Index).
  The updated list is sorted using the provided sort_by strategy.

  ## Parameters
    - `socket` - the LiveView socket
    - `msg` - the PubSub message with session_id and status
    - `assign_key` - the socket assign key that holds the agents list (default: `:agents`)
    - `sort_by` - optional sort strategy (default: from socket.assigns.sort_by)

  ## Example
      def handle_info({:agent_working, msg}, socket) do
        AgentPubSubHandlers.handle_agent_working_in_list(socket, msg, :agents, socket.assigns.sort_by)
      end
  """
  def handle_agent_working_in_list(socket, msg, assign_key \\ :agents, sort_by \\ nil) do
    sort_by = sort_by || socket.assigns[:sort_by]

    AgentStatusHelpers.handle_agent_working(socket, msg, fn socket, session_id ->
      update_agent_list(socket, assign_key, session_id, "working", sort_by)
    end)
  end

  @doc """
  Generic handle_info for :agent_stopped events that updates a list of agents.

  Used by LiveViews that maintain agents in a simple list. Extracts status from
  the message and applies it. The updated list is sorted using the provided
  sort_by strategy.

  ## Parameters
    - `socket` - the LiveView socket
    - `msg` - the PubSub message with session_id and status
    - `assign_key` - the socket assign key that holds the agents list (default: `:agents`)
    - `sort_by` - optional sort strategy (default: from socket.assigns.sort_by)

  ## Example
      def handle_info({:agent_stopped, msg}, socket) do
        AgentPubSubHandlers.handle_agent_stopped_in_list(socket, msg, :agents, socket.assigns.sort_by)
      end
  """
  def handle_agent_stopped_in_list(socket, msg, assign_key \\ :agents, sort_by \\ nil) do
    sort_by = sort_by || socket.assigns[:sort_by]

    AgentStatusHelpers.handle_agent_stopped(socket, msg, fn socket, session_id ->
      status = extract_stopped_status(msg)
      update_agent_list(socket, assign_key, session_id, status, sort_by)
    end)
  end

  @doc """
  Handle :agent_working with MapSet-based status tracking.

  Used by LiveViews that track working/waiting sessions as MapSets
  (e.g., ProjectLive.Kanban).

  ## Example
      def handle_info({:agent_working, msg}, socket) do
        AgentPubSubHandlers.handle_agent_working_mapsets(socket, msg)
      end
  """
  def handle_agent_working_mapsets(socket, msg) do
    AgentStatusHelpers.handle_agent_working(socket, msg, fn socket, session_id ->
      socket
      |> assign(:working_session_ids, MapSet.put(socket.assigns.working_session_ids, session_id))
      |> assign(
        :waiting_session_ids,
        MapSet.delete(socket.assigns.waiting_session_ids, session_id)
      )
    end)
  end

  @doc """
  Handle :agent_stopped for waiting status with MapSet tracking.

  When a session stops with "waiting" status, move it from working to waiting.
  """
  def handle_agent_stopped_waiting_mapsets(socket, %{status: "waiting", id: session_id}) do
    socket =
      socket
      |> assign(
        :working_session_ids,
        MapSet.delete(socket.assigns.working_session_ids, session_id)
      )
      |> assign(:waiting_session_ids, MapSet.put(socket.assigns.waiting_session_ids, session_id))

    {:noreply, socket}
  end

  def handle_agent_stopped_waiting_mapsets(socket, _msg), do: {:noreply, socket}

  @doc """
  Handle :agent_stopped with MapSet-based status tracking (general case).

  Removes the session from both working and waiting MapSets.

  ## Example
      def handle_info({:agent_stopped, msg}, socket) do
        AgentPubSubHandlers.handle_agent_stopped_mapsets(socket, msg)
      end
  """
  def handle_agent_stopped_mapsets(socket, msg) do
    AgentStatusHelpers.handle_agent_stopped(socket, msg, fn socket, session_id ->
      socket
      |> assign(
        :working_session_ids,
        MapSet.delete(socket.assigns.working_session_ids, session_id)
      )
      |> assign(
        :waiting_session_ids,
        MapSet.delete(socket.assigns.waiting_session_ids, session_id)
      )
    end)
  end

  @doc """
  Shared update logic for simple agent lists.

  Updates agents in the specified assign key, applies status change, and re-sorts.
  """
  def update_agent_list(socket, assign_key, session_id, new_status, sort_by) do
    now = DateTime.utc_now()

    updated_agents =
      socket.assigns[assign_key]
      |> Enum.map(&AgentStatusHelpers.apply_agent_status(&1, session_id, new_status, now))
      |> maybe_sort(sort_by)

    assign(socket, assign_key, updated_agents)
  end

  @doc """
  Extract the effective status from an agent_stopped message.

  Returns the status field if present and non-empty, otherwise defaults to "idle".
  """
  def extract_stopped_status(%{status: status}) when is_binary(status) and status != "",
    do: status

  def extract_stopped_status(%{status: _}), do: "idle"
  def extract_stopped_status(_), do: "idle"

  # Private helpers

  defp maybe_sort(agents, nil), do: agents
  defp maybe_sort(agents, ""), do: agents

  defp maybe_sort(agents, sort_by) do
    SessionFilters.sort_agents(agents, sort_by)
  end
end
