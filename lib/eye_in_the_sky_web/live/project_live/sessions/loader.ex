defmodule EyeInTheSkyWeb.ProjectLive.Sessions.Loader do
  @moduledoc """
  Handles all data-loading, filtering, sorting, pagination, and stream assignment
  for the project sessions LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4, stream_insert: 3]
  import EyeInTheSkyWeb.Helpers.SessionFilters

  alias EyeInTheSky.Sessions
  alias EyeInTheSkyWeb.ProjectLive.Sessions.State
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers

  @telemetry_prefix [:eye_in_the_sky, :project_sessions]

  @doc "Reload sessions from the database and rebuild the view."
  def load_agents(socket) do
    project_id = socket.assigns.project_id
    include_archived = socket.assigns.session_filter == "archived"

    {duration_us, all_agents} =
      :timer.tc(fn ->
        Sessions.list_project_sessions_with_agent(project_id, include_archived: include_archived)
      end)

    :telemetry.execute(
      @telemetry_prefix ++ [:load_agents],
      %{duration_us: duration_us, count: length(all_agents)},
      %{project_id: project_id, include_archived: include_archived}
    )

    socket
    |> assign(:all_agents, all_agents)
    |> apply_agent_view(true)
  end

  @doc "Reapply filter/sort/pagination on the already-loaded agent list."
  def apply_agent_view(socket, reset_page \\ false) do
    visible_count = if reset_page, do: State.page_size(), else: socket.assigns.visible_count

    {duration_us, {ordered_agents, depths}} =
      :timer.tc(fn ->
        socket.assigns.all_agents
        |> filter_agents_by_status(socket.assigns.session_filter)
        |> filter_agents_by_search(socket.assigns.search_query)
        |> sort_agents(socket.assigns.sort_by)
        |> build_tree_order()
      end)

    :telemetry.execute(
      @telemetry_prefix ++ [:apply_view],
      %{duration_us: duration_us, count: length(ordered_agents)},
      %{
        project_id: socket.assigns.project_id,
        filter: socket.assigns.session_filter,
        sort_by: socket.assigns.sort_by,
        search_query_length: String.length(socket.assigns.search_query || "")
      }
    )

    socket =
      socket
      |> assign(:agents, ordered_agents)
      |> assign(:depths, depths)
      |> assign(:visible_count, visible_count)
      |> assign(:has_more, length(ordered_agents) > visible_count)

    visible_agents = Enum.take(ordered_agents, visible_count)

    if reset_page do
      stream(socket, :session_list, visible_agents, reset: true, dom_id: fn a -> "ps-#{a.id}" end)
    else
      Enum.reduce(visible_agents, socket, fn agent, acc ->
        stream_insert(acc, :session_list, agent)
      end)
    end
  end

  @doc "Update a single session's status in-memory and re-render only that row."
  def update_agent_status_in_list(socket, session_id, new_status) do
    now = DateTime.utc_now()

    updated =
      Enum.map(
        socket.assigns.all_agents,
        &AgentStatusHelpers.apply_agent_status(&1, session_id, new_status, now)
      )

    socket = assign(socket, :all_agents, updated)

    # Only stream_insert the changed row — inserting every visible agent causes the
    # stream's remove→morph→reinsert cycle on all rows, which resets :hover state
    # and makes the ... menu flicker via its opacity transition.
    case Enum.find(updated, &(&1.id == session_id)) do
      nil ->
        socket

      changed_agent ->
        agents =
          Enum.map(socket.assigns.agents, fn a ->
            if a.id == session_id, do: changed_agent, else: a
          end)

        socket
        |> assign(:agents, agents)
        |> stream_insert(:session_list, changed_agent)
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp build_tree_order(sessions) do
    session_ids = MapSet.new(sessions, & &1.id)

    {children, top_level} =
      Enum.split_with(sessions, fn s ->
        not is_nil(s.parent_session_id) && MapSet.member?(session_ids, s.parent_session_id)
      end)

    children_by_parent = Enum.group_by(children, & &1.parent_session_id)

    ordered =
      Enum.flat_map(top_level, fn parent ->
        kids = Map.get(children_by_parent, parent.id, [])
        [parent | kids]
      end)

    depths =
      Map.new(top_level, &{&1.id, 0})
      |> Map.merge(Map.new(children, &{&1.id, 1}))

    {ordered, depths}
  end
end
