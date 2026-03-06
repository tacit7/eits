defmodule EyeInTheSkyWebWeb.ProjectLive.Sessions do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Sessions
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers
  import EyeInTheSkyWebWeb.Components.Icons

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
        |> assign(:selected_ids, MapSet.new())
        |> assign(:agents, [])
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

    agents =
      Sessions.list_sessions_with_agent(include_archived: include_archived)
      |> Enum.filter(&(&1.project_id == project_id))
      |> filter_agents_by_status(socket.assigns.session_filter)
      |> filter_agents_by_search(socket.assigns.search_query)
      |> sort_agents(socket.assigns.sort_by)

    assign(socket, :agents, agents)
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

    updated_agents =
      socket.assigns.agents
      |> Enum.map(fn agent ->
        if agent.id == session_id do
          agent = %{agent | status: new_status}
          if new_status == "idle", do: %{agent | last_activity_at: now}, else: agent
        else
          agent
        end
      end)
      |> sort_agents(socket.assigns.sort_by)

    assign(socket, :agents, updated_agents)
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 3, do: query, else: ""

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> load_agents()

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
      |> load_agents()

    {:noreply, socket}
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
      instructions: description
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
    {:noreply, push_navigate(socket, to: ~p"/dm/#{id}")}
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
    <div class="bg-base-100 min-h-screen px-6 lg:px-8">
      <div class="max-w-3xl mx-auto">
        <%!-- Toolbar --%>
        <div class="flex items-center justify-between py-5">
          <span class="text-[11px] font-mono tabular-nums text-base-content/30 tracking-wider uppercase">
            {length(@agents)} sessions
          </span>
          <button
            phx-click="toggle_new_session_drawer"
            class="btn btn-sm btn-primary gap-1.5 min-h-0 h-7 text-xs"
          >
            <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Agent
          </button>
        </div>

        <%!-- Search and Filters --%>
        <div class="sticky top-16 z-10 bg-base-100/85 backdrop-blur-md -mx-6 lg:-mx-8 px-6 lg:px-8 py-3 border-b border-base-content/5">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-3">
            <form phx-submit="search" phx-change="search" class="flex-1 max-w-sm">
              <div class="relative">
                <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                  <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
                </div>
                <input
                  type="text"
                  name="query"
                  id="search"
                  value={@search_query}
                  phx-debounce="300"
                  class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-sm"
                  placeholder="Search..."
                />
              </div>
            </form>

            <div class="flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
              <%= for {label, filter, active_class} <- [
                {"All", "all", "bg-base-100 text-base-content shadow-sm"},
                {"Active", "active", "bg-base-100 text-success shadow-sm"},
                {"Completed", "completed", "bg-base-100 text-base-content shadow-sm"},
                {"Archived", "archived", "bg-base-100 text-warning shadow-sm"}
              ] do %>
                <button
                  phx-click="filter_session"
                  phx-value-filter={filter}
                  class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                    if(@session_filter == filter,
                      do: active_class,
                      else: "text-base-content/40 hover:text-base-content/60"
                    )}
                >
                  {label}
                </button>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Selection toolbar (archived view) --%>
        <%= if @session_filter == "archived" && @agents != [] do %>
          <div class="mt-2 flex items-center gap-3 px-2 py-1.5">
            <input
              type="checkbox"
              checked={MapSet.size(@selected_ids) == length(@agents) && @agents != []}
              phx-click="toggle_select_all"
              class="checkbox checkbox-xs checkbox-primary"
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
        <div class="mt-2 divide-y divide-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm px-4">
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
            <%= for agent <- @agents do %>
              <% display_status = EyeInTheSkyWebWeb.Helpers.ViewHelpers.derive_display_status(agent) %>
              <% {status_color, status_bg, status_label, is_active} =
                case display_status do
                  "working" -> {"text-success", "bg-success", "Working", true}
                  "compacting" -> {"text-warning", "bg-warning", "Compacting", true}
                  "idle" -> {"text-base-content/25", "bg-base-content/20", "Idle", false}
                  "idle_stale" -> {"text-warning", "bg-warning", "Idle", false}
                  "idle_dead" -> {"text-error", "bg-error", "Idle", false}
                  "completed" -> {"text-base-content/25", "bg-base-content/20", "Done", false}
                  _ -> {"text-base-content/25", "bg-base-content/20", "Idle", false}
                end %>
              <div
                class="group flex items-center gap-4 py-3 px-2 -mx-2 rounded-lg cursor-pointer"
                phx-click="navigate_dm"
                phx-value-id={agent.id}
              >
                <%!-- Status indicator / checkbox --%>
                <%= if @session_filter == "archived" do %>
                  <div class="flex-shrink-0 w-6 flex justify-center">
                    <input
                      type="checkbox"
                      checked={MapSet.member?(@selected_ids, to_string(agent.id))}
                      phx-click="toggle_select"
                      phx-value-id={agent.id}
                      class="checkbox checkbox-xs checkbox-primary"
                    />
                  </div>
                <% else %>
                  <div class="flex-shrink-0 w-6 flex justify-center" title={status_label}>
                    <%= if is_active do %>
                      <span class="relative flex h-2 w-2">
                        <span class={"animate-ping absolute inline-flex h-full w-full rounded-full opacity-50 " <> status_bg}>
                        </span>
                        <span class={"relative inline-flex rounded-full h-2 w-2 " <> status_bg}>
                        </span>
                      </span>
                    <% else %>
                      <span class={"inline-flex rounded-full h-2 w-2 " <> status_bg}></span>
                    <% end %>
                  </div>
                <% end %>

                <%!-- Main content --%>
                <div class="flex-1 min-w-0">
                  <div class="flex items-baseline gap-2">
                    <span class="text-[13px] font-medium text-base-content/85 truncate">
                      {agent.name || "Unnamed session"}
                    </span>
                    <span class={"text-[10px] font-medium uppercase tracking-wider " <> status_color}>
                      {status_label}
                    </span>
                  </div>
                  <div class="flex items-center gap-1.5 mt-1 text-[11px] text-base-content/30">
                    <span class="font-mono">{Sessions.format_model_info(agent)}</span>
                    <span class="text-base-content/15">/</span>
                    <span class="tabular-nums">{relative_time(agent.started_at)}</span>
                  </div>
                  <%= if agent.agent && agent.agent.description do %>
                    <p class="text-xs text-base-content/35 mt-1 truncate max-w-lg">
                      {agent.agent.description}
                    </p>
                  <% end %>
                </div>

                <%!-- Actions --%>
                <div class="flex items-center gap-0.5 flex-shrink-0" phx-click="noop">
                  <%= if agent.id do %>
                    <a
                      href={~p"/dm/#{agent.id}"}
                      target="_blank"
                      class="btn btn-ghost btn-xs btn-square text-base-content/30 hover:text-primary"
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
                      class="bookmark-button btn btn-ghost btn-xs btn-square text-base-content/30 hover:text-error"
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
                        class="btn btn-ghost btn-xs btn-square text-base-content/30 hover:text-info"
                        aria-label="Unarchive"
                      >
                        <.icon name="hero-arrow-up-tray-mini" class="w-3.5 h-3.5" />
                      </button>
                      <button
                        type="button"
                        phx-click="delete_session"
                        phx-value-session_id={agent.id}
                        class="btn btn-ghost btn-xs btn-square text-base-content/30 hover:text-error"
                        aria-label="Delete"
                      >
                        <.icon name="hero-trash-mini" class="w-3.5 h-3.5" />
                      </button>
                    <% else %>
                      <button
                        type="button"
                        phx-click="archive_session"
                        phx-value-session_id={agent.id}
                        class="btn btn-ghost btn-xs btn-square text-base-content/30 hover:text-warning"
                        aria-label="Archive"
                      >
                        <.icon name="hero-archive-box-mini" class="w-3.5 h-3.5" />
                      </button>
                    <% end %>
                  <% end %>
                </div>

                <%!-- Chevron --%>
                <div class="flex-shrink-0">
                  <.icon name="hero-chevron-right-mini" class="w-4 h-4 text-base-content/20" />
                </div>
              </div>
            <% end %>
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
