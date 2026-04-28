defmodule EyeInTheSkyWeb.ProjectLive.Sessions.Loader do
  @moduledoc """
  Handles all data-loading, filtering, sorting, pagination, and stream assignment
  for the project sessions LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4, stream_insert: 3, stream_delete_by_dom_id: 3]
  import EyeInTheSkyWeb.Helpers.SessionFilters

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Sessions
  alias EyeInTheSkyWeb.ProjectLive.Sessions.Selection
  alias EyeInTheSkyWeb.ProjectLive.Sessions.State
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers

  @telemetry_prefix [:eye_in_the_sky, :project_sessions]

  @doc "Reload sessions from the database and rebuild the view."
  def load_agents(socket) do
    scope = Map.get(socket.assigns, :scope, socket.assigns.project_id)
    include_archived = socket.assigns.session_filter == "archived"

    {duration_us, all_agents} =
      :timer.tc(fn ->
        load_sessions_for_scope(scope, include_archived)
      end)

    :telemetry.execute(
      @telemetry_prefix ++ [:load_agents],
      %{duration_us: duration_us, count: length(all_agents)},
      %{scope: scope, include_archived: include_archived}
    )

    socket
    |> assign(:all_agents, all_agents)
    |> apply_agent_view(true)
  end

  defp load_sessions_for_scope(:all, include_archived) do
    Sessions.list_sessions_with_agent(include_archived: include_archived)
    |> attach_project_names()
  end

  defp load_sessions_for_scope(project_id, include_archived) when is_integer(project_id) do
    Sessions.list_project_sessions_with_agent(project_id, include_archived: include_archived)
  end

  defp load_sessions_for_scope(_, _), do: []

  defp attach_project_names([]), do: []

  defp attach_project_names(sessions) do
    names_by_id =
      Projects.list_projects()
      |> Map.new(&{&1.id, &1.name})

    Enum.map(sessions, fn s ->
      Map.put(s, :project_name, Map.get(names_by_id, s.project_id))
    end)
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
      |> recompute_selection_metadata()

    visible_agents = Enum.take(ordered_agents, visible_count)

    if reset_page do
      stream(socket, :session_list, visible_agents, reset: true, dom_id: fn a -> "ps-#{a.id}" end)
    else
      Enum.reduce(visible_agents, socket, fn agent, acc ->
        stream_insert(acc, :session_list, agent)
      end)
    end
  end

  defp recompute_selection_metadata(socket) do
    # Guard against missing assigns on first mount before State.init runs
    selected = Map.get(socket.assigns, :selected_ids, MapSet.new())
    agents = Map.get(socket.assigns, :agents, [])

    socket
    |> assign(:off_screen_selected_count, Selection.off_screen_count(selected, agents))
    |> assign(:indeterminate_ids, Selection.compute_indeterminate_ids(selected, agents))
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

    # Re-apply filter/sort so @agents, @depths, and @has_more stay consistent
    # with any sort_by that depends on status (e.g. "status", "last_message").
    # Then only stream_insert the one changed row — bulk stream_insert triggers
    # the stream's remove→morph→reinsert cycle on every row, which resets :hover
    # and makes the ... button flicker via its opacity classes.
    {ordered_agents, depths} =
      updated
      |> filter_agents_by_status(socket.assigns.session_filter)
      |> filter_agents_by_search(socket.assigns.search_query)
      |> sort_agents(socket.assigns.sort_by)
      |> build_tree_order()

    visible_count = socket.assigns.visible_count
    visible_agents = Enum.take(ordered_agents, visible_count)

    socket =
      socket
      |> assign(:agents, ordered_agents)
      |> assign(:depths, depths)
      |> assign(:has_more, length(ordered_agents) > visible_count)

    # Guard: skip stream_insert when the changed session is outside the visible
    # slice — inserting off-screen IDs into the stream breaks pagination.
    case Enum.find(visible_agents, &(&1.id == session_id)) do
      nil -> socket
      changed_agent -> stream_insert(socket, :session_list, changed_agent)
    end
  end

  @doc """
  Remove a session from the in-memory list and stream-delete its row.

  Used by archive/unarchive/delete handlers so the page doesn't jump from
  a full `stream(..., reset: true)` rebuild. Only the affected row is
  removed from the DOM; surrounding rows keep their identity and the
  user's scroll position is preserved.
  """
  def remove_agent_from_list(socket, session_id) do
    updated = Enum.reject(socket.assigns.all_agents, &(&1.id == session_id))

    {ordered_agents, depths} =
      updated
      |> filter_agents_by_status(socket.assigns.session_filter)
      |> filter_agents_by_search(socket.assigns.search_query)
      |> sort_agents(socket.assigns.sort_by)
      |> build_tree_order()

    visible_count = socket.assigns.visible_count

    socket
    |> assign(:all_agents, updated)
    |> assign(:agents, ordered_agents)
    |> assign(:depths, depths)
    |> assign(:has_more, length(ordered_agents) > visible_count)
    |> stream_delete_by_dom_id(:session_list, "ps-#{session_id}")
  end

  @doc """
  Reload a single session from DB and upsert it into the in-memory list,
  then do a targeted stream_insert of just that row.
  Avoids full stream reset flicker on session_updated events.
  """
  def upsert_agent_in_list(socket, session_id) do
    scope = Map.get(socket.assigns, :scope, socket.assigns.project_id)
    refreshed = Sessions.get_session_with_agent(session_id)

    cond do
      is_nil(refreshed) ->
        remove_agent_from_list(socket, session_id)

      is_integer(scope) and refreshed.project_id != scope ->
        socket

      true ->
        refreshed = maybe_attach_project_name(refreshed, socket)

        updated =
          if Enum.any?(socket.assigns.all_agents, &(&1.id == session_id)) do
            Enum.map(socket.assigns.all_agents, fn s ->
              if s.id == session_id, do: refreshed, else: s
            end)
          else
            [refreshed | socket.assigns.all_agents]
          end

        socket = assign(socket, :all_agents, updated)

        {ordered_agents, depths} =
          updated
          |> filter_agents_by_status(socket.assigns.session_filter)
          |> filter_agents_by_search(socket.assigns.search_query)
          |> sort_agents(socket.assigns.sort_by)
          |> build_tree_order()

        visible_count = socket.assigns.visible_count
        visible_agents = Enum.take(ordered_agents, visible_count)

        socket =
          socket
          |> assign(:agents, ordered_agents)
          |> assign(:depths, depths)
          |> assign(:has_more, length(ordered_agents) > visible_count)

        case Enum.find(visible_agents, &(&1.id == session_id)) do
          nil -> socket
          changed -> stream_insert(socket, :session_list, changed)
        end
    end
  end

  defp maybe_attach_project_name(session, socket) do
    if socket.assigns.scope == :all do
      names_by_id =
        Projects.list_projects()
        |> Map.new(&{&1.id, &1.name})

      Map.put(session, :project_name, Map.get(names_by_id, session.project_id))
    else
      session
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
