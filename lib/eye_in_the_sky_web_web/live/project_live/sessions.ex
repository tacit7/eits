defmodule EyeInTheSkyWebWeb.ProjectLive.Sessions do
  use EyeInTheSkyWebWeb, :live_view

  @telemetry_prefix [:eye_in_the_sky_web, :project_sessions]
  @page_size 25

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Sessions
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers
  import EyeInTheSkyWebWeb.Components.Icons
  import EyeInTheSkyWebWeb.Components.SessionCard

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project_id =
      case Integer.parse(id) do
        {int, ""} -> int
        _ -> nil
      end

    if project_id do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agents")
        Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
      end

      project = Projects.get_project!(project_id)

      socket =
        socket
        |> assign(:page_title, "Sessions - #{project.name}")
        |> assign(:project, project)
        |> assign(:sidebar_tab, :sessions)
        |> assign(:sidebar_project, project)
        |> assign(:project_id, project_id)
        |> assign(:search_query, "")
        |> assign(:sort_by, "recent")
        |> assign(:session_filter, "all")
        |> assign(:show_new_session_drawer, false)
        |> assign(:show_filter_sheet, false)
        |> assign(:selected_ids, MapSet.new())
        |> assign(:all_agents, [])
        |> assign(:agents, [])
        |> assign(:visible_count, @page_size)
        |> assign(:has_more, false)
        |> assign(:list_version, 0)
        |> load_agents()

      {:ok, socket}
    else
      {:ok,
       socket
       |> assign(:page_title, "Project Not Found")
       |> put_flash(:error, "Invalid project ID")}
    end
  end

  defp load_agents(socket) do
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

  defp apply_agent_view(socket, reset_page \\ false) do
    visible_count = if reset_page, do: @page_size, else: socket.assigns.visible_count

    {duration_us, agents} =
      :timer.tc(fn ->
        socket.assigns.all_agents
        |> filter_agents_by_status(socket.assigns.session_filter)
        |> filter_agents_by_search(socket.assigns.search_query)
        |> sort_agents(socket.assigns.sort_by)
      end)

    :telemetry.execute(
      @telemetry_prefix ++ [:apply_view],
      %{duration_us: duration_us, count: length(agents)},
      %{
        project_id: socket.assigns.project_id,
        filter: socket.assigns.session_filter,
        sort_by: socket.assigns.sort_by,
        search_query_length: String.length(socket.assigns.search_query || "")
      }
    )

    socket =
      socket
      |> assign(:agents, agents)
      |> assign(:visible_count, visible_count)
      |> assign(:has_more, length(agents) > visible_count)

    if reset_page, do: update(socket, :list_version, &(&1 + 1)), else: socket
  end

  defp filter_agents_by_status(sessions, filter) do
    case filter do
      "active" ->
        Enum.filter(sessions, &(&1.status in ["working", "idle", nil] and is_nil(&1.archived_at)))

      "completed" ->
        Enum.filter(sessions, &(&1.status == "completed" and is_nil(&1.archived_at)))

      "archived" ->
        Enum.filter(sessions, &(!is_nil(&1.archived_at)))

      _ ->
        sessions
    end
  end

  defp filter_agents_by_search(sessions, query) do
    q = (query || "") |> String.trim() |> String.downcase()

    if q == "" do
      sessions
    else
      Enum.filter(sessions, fn s ->
        haystack =
          [s.uuid, s.name, s.agent && s.agent.description]
          |> Enum.map(&to_string_or_empty/1)
          |> Enum.join(" ")
          |> String.downcase()

        String.contains?(haystack, q)
      end)
    end
  end

  defp sort_agents(sessions, sort_by) do
    case sort_by do
      "name" ->
        Enum.sort_by(sessions, fn s -> (s.name || "") |> String.downcase() end)

      "status" ->
        Enum.sort_by(sessions, &status_rank/1)

      _ ->
        Enum.sort_by(
          sessions,
          fn s -> sort_datetime(s.last_activity_at || s.started_at) end,
          {:desc, NaiveDateTime}
        )
    end
  end

  defp status_rank(agent) do
    case agent.status do
      "discovered" -> 0
      "working" -> 1
      "idle" -> 1
      "completed" -> 2
      nil -> 1
      _ -> 2
    end
  end

  defp to_string_or_empty(nil), do: ""
  defp to_string_or_empty(v) when is_binary(v), do: v
  defp to_string_or_empty(v), do: to_string(v)

  defp sort_datetime(%NaiveDateTime{} = ndt), do: ndt
  defp sort_datetime(%DateTime{} = dt), do: DateTime.to_naive(dt)
  defp sort_datetime(_), do: ~N[0000-01-01 00:00:00]

  defp update_agent_status_in_list(socket, session_id, new_status) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    update_status = fn agents ->
      agents
      |> Enum.map(fn agent ->
        if agent.id == session_id do
          agent = %{agent | status: new_status}
          if new_status == "idle", do: %{agent | last_activity_at: now}, else: agent
        else
          agent
        end
      end)
    end

    socket
    |> assign(:all_agents, update_status.(socket.assigns.all_agents))
    |> apply_agent_view()
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 3, do: query, else: ""

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> apply_agent_view(true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_session", %{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:session_filter, filter)
      |> assign(:selected_ids, MapSet.new())
      |> load_agents()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"by" => sort_by}, socket) do
    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> apply_agent_view(true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    if socket.assigns.has_more do
      new_count = socket.assigns.visible_count + @page_size

      socket =
        socket
        |> assign(:visible_count, new_count)
        |> assign(:has_more, length(socket.assigns.agents) > new_count)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_filter_sheet", _params, socket) do
    {:noreply, assign(socket, :show_filter_sheet, true)}
  end

  @impl true
  def handle_event("close_filter_sheet", _params, socket) do
    {:noreply, assign(socket, :show_filter_sheet, false)}
  end

  @impl true
  def handle_event("toggle_new_session_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_session_drawer, !socket.assigns.show_new_session_drawer)}
  end

  @impl true
  def handle_event("create_new_session", params, socket) do
    require Logger

    agent_type = params["agent_type"] || "claude"
    model = params["model"]
    effort_level = params["effort_level"]
    project = socket.assigns.project
    description = params["description"]
    agent_name = params["agent_name"] || String.slice(description || "", 0, 60)

    opts = [
      agent_type: agent_type,
      model: model,
      effort_level: effort_level,
      project_id: project.id,
      project_path: project.path,
      description: agent_name,
      instructions: description,
      agent: params["agent"]
    ]

    case EyeInTheSkyWeb.Claude.AgentManager.create_agent(opts) do
      {:ok, _result} ->
        socket =
          socket
          |> assign(:show_new_session_drawer, false)
          |> load_agents()
          |> put_flash(:info, "Session launched")

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("create_new_session failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("archive_session", %{"session_id" => session_id}, socket) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.archive_session(session) do
      {:noreply, socket |> load_agents() |> put_flash(:info, "Session archived")}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to archive session")}
    end
  end

  @impl true
  def handle_event("unarchive_session", %{"session_id" => session_id}, socket) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.unarchive_session(session) do
      {:noreply, socket |> load_agents() |> put_flash(:info, "Session unarchived")}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to unarchive session")}
    end
  end

  @impl true
  def handle_event("delete_session", %{"session_id" => session_id}, socket) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.delete_session(session) do
      {:noreply, socket |> load_agents() |> put_flash(:info, "Session deleted")}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to delete session")}
    end
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_ids, id),
        do: MapSet.delete(socket.assigns.selected_ids, id),
        else: MapSet.put(socket.assigns.selected_ids, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    all_ids = MapSet.new(socket.assigns.agents, &to_string(&1.id))

    selected =
      if MapSet.equal?(socket.assigns.selected_ids, all_ids),
        do: MapSet.new(),
        else: all_ids

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("delete_selected", _params, socket) do
    results =
      Enum.map(socket.assigns.selected_ids, fn id ->
        with {:ok, session} <- Sessions.get_session(id),
             {:ok, _} <- Sessions.delete_session(session) do
          :ok
        else
          _ -> :error
        end
      end)

    deleted = Enum.count(results, &(&1 == :ok))

    socket =
      socket
      |> assign(:selected_ids, MapSet.new())
      |> load_agents()
      |> put_flash(:info, "Deleted #{deleted} session#{if deleted != 1, do: "s"}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("navigate_dm", %{"id" => id}, socket) do
    project_id = socket.assigns.project_id
    {:noreply, push_navigate(socket, to: ~p"/dm/#{id}?from=project&project_id=#{project_id}")}
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:agent_updated, _agent}, socket) do
    {:noreply, load_agents(socket)}
  end

  @impl true
  def handle_info({:agent_working, _session_uuid, session_id}, socket) do
    {:noreply, update_agent_status_in_list(socket, session_id, "working")}
  end

  @impl true
  def handle_info({:agent_stopped, _session_uuid, session_id}, socket) do
    {:noreply, update_agent_status_in_list(socket, session_id, "idle")}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-100 min-h-full px-4 sm:px-6 lg:px-8">
      <div class="max-w-4xl mx-auto">
        <%!-- Toolbar --%>
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between py-5">
          <span class="text-[11px] font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
            <%= if @has_more do %>
              {min(@visible_count, length(@agents))} of {length(@agents)} sessions
            <% else %>
              {length(@agents)} sessions
            <% end %>
          </span>
          <button
            phx-click="toggle_new_session_drawer"
            class="btn btn-sm btn-primary gap-1.5 min-h-0 h-8 sm:h-7 text-xs w-full sm:w-auto"
          >
            <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Agent
          </button>
        </div>

        <%!-- Search and Filters --%>
        <div class="sticky safe-top-sticky md:top-16 z-10 bg-base-100/85 backdrop-blur-md -mx-4 sm:-mx-6 lg:-mx-8 px-4 sm:px-6 lg:px-8 py-3 border-b border-base-content/5">
          <div class="flex items-center gap-3">
            <form phx-submit="search" phx-change="search" class="flex-1 sm:max-w-sm">
              <div class="relative">
                <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                  <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
                </div>
                <label for="project-sessions-search" class="sr-only">Search sessions</label>
                <input
                  type="text"
                  name="query"
                  id="project-sessions-search"
                  value={@search_query}
                  phx-debounce="300"
                  class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-sm"
                  placeholder="Search..."
                />
              </div>
            </form>

            <%!-- Desktop filter pills (hidden on mobile) --%>
            <div class="hidden sm:flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
              <%= for {label, filter, active_class} <- [
                {"All", "all", "bg-base-100 text-base-content shadow-sm"},
                {"Active", "active", "bg-base-100 text-success shadow-sm"},
                {"Completed", "completed", "bg-base-100 text-base-content shadow-sm"},
                {"Archived", "archived", "bg-base-100 text-warning shadow-sm"}
              ] do %>
                <button
                  phx-click="filter_session"
                  phx-value-filter={filter}
                  aria-pressed={@session_filter == filter}
                  class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                    if(@session_filter == filter,
                      do: active_class,
                      else: "text-base-content/60 hover:text-base-content/85"
                    )}
                >
                  {label}
                </button>
              <% end %>
            </div>

            <%!-- Mobile filter button (hidden on sm+) --%>
            <button
              phx-click="open_filter_sheet"
              aria-label="Open filters"
              aria-haspopup="dialog"
              class="sm:hidden relative btn btn-ghost btn-sm btn-square"
            >
              <.icon name="hero-funnel-mini" class="w-4 h-4" />
              <%= if @session_filter != "all" || @sort_by != "recent" do %>
                <span class="absolute top-0.5 right-0.5 w-2 h-2 bg-primary rounded-full" aria-hidden="true"></span>
              <% end %>
            </button>
          </div>
        </div>

        <%!-- Mobile filter bottom sheet --%>
        <%= if @show_filter_sheet do %>
          <div
            class="fixed inset-0 z-40 bg-black/40"
            phx-click="close_filter_sheet"
            aria-hidden="true"
          >
          </div>
          <div
            class="fixed inset-x-0 bottom-0 z-50 rounded-t-2xl bg-base-100 shadow-xl safe-bottom-sheet"
            role="dialog"
            aria-modal="true"
            aria-label="Filter sessions"
            id="session-filter-sheet"
            phx-window-keydown="close_filter_sheet"
            phx-key="Escape"
          >
            <div class="flex justify-center pt-3 pb-1">
              <div class="w-10 h-1 rounded-full bg-base-content/20"></div>
            </div>
            <div class="px-5 pb-6 pt-2">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-sm font-semibold">Filter &amp; Sort</h2>
                <button
                  phx-click="close_filter_sheet"
                  class="btn btn-ghost btn-xs btn-square"
                  aria-label="Close filter panel"
                >
                  <.icon name="hero-x-mark-mini" class="w-4 h-4" />
                </button>
              </div>

              <fieldset class="mb-5">
                <legend class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-2">Status</legend>
                <div class="flex flex-wrap gap-2">
                  <%= for {label, filter} <- [
                    {"All", "all"},
                    {"Active", "active"},
                    {"Completed", "completed"},
                    {"Archived", "archived"}
                  ] do %>
                    <button
                      phx-click="filter_session"
                      phx-value-filter={filter}
                      aria-pressed={@session_filter == filter}
                      class={"btn btn-sm " <>
                        if(@session_filter == filter,
                          do: "btn-primary",
                          else: "btn-ghost border border-base-content/15"
                        )}
                    >
                      {label}
                    </button>
                  <% end %>
                </div>
              </fieldset>

              <fieldset class="mb-6">
                <legend class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-2">Sort by</legend>
                <div class="flex flex-wrap gap-2">
                  <%= for {label, sort} <- [{"Recent", "recent"}, {"Name", "name"}, {"Status", "status"}] do %>
                    <button
                      phx-click="sort"
                      phx-value-by={sort}
                      aria-pressed={@sort_by == sort}
                      class={"btn btn-sm " <>
                        if(@sort_by == sort,
                          do: "btn-primary",
                          else: "btn-ghost border border-base-content/15"
                        )}
                    >
                      {label}
                    </button>
                  <% end %>
                </div>
              </fieldset>

              <div class="flex gap-3">
                <button
                  phx-click="close_filter_sheet"
                  class="btn btn-primary flex-1"
                >
                  Apply
                </button>
                <button
                  phx-click="filter_session"
                  phx-value-filter="all"
                  class="btn btn-ghost"
                  aria-label="Reset filters"
                >
                  Reset
                </button>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Selection toolbar (archived view) --%>
        <%= if @session_filter == "archived" && @agents != [] do %>
          <div class="mt-2 flex items-center gap-3 px-2 py-1.5">
            <input
              type="checkbox"
              checked={MapSet.size(@selected_ids) == length(@agents) && @agents != []}
              phx-click="toggle_select_all"
              class="checkbox checkbox-xs checkbox-primary"
              aria-label="Select all archived sessions"
            />
            <%= if MapSet.size(@selected_ids) > 0 do %>
              <span class="text-[11px] text-base-content/50 font-medium">
                {MapSet.size(@selected_ids)} selected
              </span>
              <button
                phx-click="delete_selected"
                class="btn btn-ghost btn-xs text-error/70 hover:text-error hover:bg-error/10 gap-1"
              >
                <.icon name="hero-trash-mini" class="w-3.5 h-3.5" /> Delete
              </button>
            <% else %>
              <span class="text-[11px] text-base-content/30">{length(@agents)} archived</span>
            <% end %>
          </div>
        <% end %>

        <%!-- Session list --%>
        <div class="mt-2 rounded-xl shadow-sm">
          <%= if @agents == [] do %>
            <.empty_state
              id="project-sessions-empty"
              title="No sessions found"
              subtitle={
                if @search_query != "" || @session_filter != "all",
                  do: "Try adjusting your search or filters",
                  else: "Sessions will appear here when agents start working on this project"
              }
            />
          <% else %>
            <div
              id={"ps-list-#{@list_version}"}
              phx-update="append"
              class="divide-y divide-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl px-4"
            >
            <%= for agent <- Enum.take(@agents, @visible_count) do %>
              <div id={"ps-#{agent.id}"}>
                <.session_row
                  session={agent}
                  select_mode={@session_filter == "archived"}
                  selected={MapSet.member?(@selected_ids, to_string(agent.id))}
                >
                  <:actions>
                    <%= if agent.id do %>
                      <a
                        href={~p"/dm/#{agent.id}"}
                        target="_blank"
                        class="hidden sm:inline-flex md:opacity-0 md:group-hover:opacity-100 min-h-[44px] min-w-[44px] items-center justify-center rounded-md text-base-content/30 hover:text-primary hover:bg-primary/10 transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                        aria-label="Open in new tab"
                      >
                        <.icon name="hero-arrow-top-right-on-square-mini" class="w-3.5 h-3.5" />
                      </a>
                    <% end %>
                    <%= if agent.agent && agent.agent.uuid && agent.uuid do %>
                      <button
                        id={"bookmark-btn-#{agent.uuid}"}
                        type="button"
                        phx-hook="BookmarkAgent"
                        data-agent-id={agent.agent.uuid}
                        data-session-id={agent.uuid}
                        data-agent-name={agent.name || agent.agent.description || "Agent"}
                        data-agent-status={agent.status}
                        class="bookmark-button md:opacity-0 md:group-hover:opacity-100 min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/30 hover:text-error hover:bg-error/10 transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-error"
                        aria-label="Bookmark agent"
                      >
                        <.heart class="bookmark-icon w-3.5 h-3.5" />
                      </button>
                    <% end %>
                    <%= if agent.uuid do %>
                      <%= if agent.archived_at do %>
                        <button
                          type="button"
                          phx-click="unarchive_session"
                          phx-value-session_id={agent.id}
                          class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/30 hover:text-info hover:bg-info/10 transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-info"
                          aria-label="Unarchive"
                        >
                          <.icon name="hero-arrow-up-tray-mini" class="w-3.5 h-3.5" />
                        </button>
                        <button
                          type="button"
                          phx-click="delete_session"
                          phx-value-session_id={agent.id}
                          class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/30 hover:text-error hover:bg-error/10 transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-error"
                          aria-label="Delete"
                        >
                          <.icon name="hero-trash-mini" class="w-3.5 h-3.5" />
                        </button>
                      <% else %>
                        <button
                          type="button"
                          phx-click="archive_session"
                          phx-value-session_id={agent.id}
                          class="hidden sm:flex md:opacity-0 md:group-hover:opacity-100 min-h-[44px] min-w-[44px] items-center justify-center rounded-md text-base-content/30 hover:text-warning hover:bg-warning/10 transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-warning"
                          aria-label="Archive"
                        >
                          <.icon name="hero-archive-box-mini" class="w-3.5 h-3.5" />
                        </button>
                      <% end %>
                    <% end %>
                  </:actions>
                </.session_row>
              </div>
            <% end %>
            </div>
          <% end %>
        </div>

        <div
          id="project-sessions-sentinel"
          phx-hook="InfiniteScroll"
          data-has-more={to_string(@has_more)}
          data-page={@visible_count}
          class="py-4 flex justify-center"
        >
          <%= if @has_more do %>
            <span class="loading loading-spinner loading-sm text-base-content/30"></span>
          <% end %>
        </div>
      </div>
    </div>

    <%!-- New Session Modal --%>
    <.live_component
      module={EyeInTheSkyWebWeb.Components.NewSessionModal}
      id="new-session-modal-project"
      show={@show_new_session_drawer}
      projects={nil}
      current_project={@project}
      toggle_event="toggle_new_session_drawer"
      submit_event="create_new_session"
    />
    """
  end
end
