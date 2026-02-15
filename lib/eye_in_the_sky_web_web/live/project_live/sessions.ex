defmodule EyeInTheSkyWebWeb.ProjectLive.Sessions do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Agents
  alias EyeInTheSkyWeb.Repo
  import EyeInTheSkyWebWeb.Components.SessionCard

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Parse project ID safely, handling both integer and UUID inputs
    project_id =
      case Integer.parse(id) do
        {int, ""} -> int
        _ -> nil
      end

    socket =
      if project_id do
        project =
          Projects.get_project!(project_id)
          |> Repo.preload([:agents])

        # Load tasks manually due to type mismatch
        tasks = Projects.get_project_tasks(project_id)

        agents =
          Agents.list_execution_agent_overview_rows(
            project_id: project_id,
            limit: 50,
            search_query: ""
          )

        socket
        |> assign(:page_title, "Sessions - #{project.name}")
        |> assign(:project, project)
        |> assign(:sidebar_tab, :sessions)
        |> assign(:sidebar_project, project)
        |> assign(:tasks, tasks)
        |> assign(:search_query, "")
        |> assign(:status_filter, "all")
        |> assign(:agents, agents)
        |> assign(:show_new_session_drawer, false)
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:tasks, [])
        |> assign(:search_query, "")
        |> assign(:status_filter, "all")
        |> assign(:agents, [])
        |> assign(:filtered_agents, [])
        |> put_flash(:error, "Invalid project ID")
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 4, do: query, else: ""

    project_id = socket.assigns.project.id
    status_filter = socket.assigns.status_filter

    agents =
      Agents.list_execution_agent_overview_rows(
        project_id: project_id,
        limit: 50,
        search_query: effective_query
      )

    filtered_agents = apply_status_filter(agents, status_filter)

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> assign(:agents, filtered_agents)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    # Apply status filter to current sessions
    filtered_agents = apply_status_filter(socket.assigns.agents, status)

    socket =
      socket
      |> assign(:status_filter, status)
      |> assign(:agents, filtered_agents)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_new_session_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_session_drawer, !socket.assigns.show_new_session_drawer)}
  end

  @impl true
  def handle_event("create_new_session", params, socket) do
    alias EyeInTheSkyWeb.Claude.SessionManager

    model = params["model"]
    description = params["description"]
    project = socket.assigns.project

    session_id = Ecto.UUID.generate()
    agent_id = Ecto.UUID.generate()

    prompt =
      "Start new eits session: session-id #{session_id} agent-id #{agent_id} description: #{description}"

    Task.Supervisor.start_child(EyeInTheSkyWeb.TaskSupervisor, fn ->
      SessionManager.start_session(session_id, prompt,
        model: model,
        project_path: project.path
      )
    end)

    socket =
      socket
      |> assign(:show_new_session_drawer, false)
      |> put_flash(:info, "Session launched — Claude Code will register with EITS")

    {:noreply, socket}
  end

  defp apply_status_filter(agents, status_filter) do
    Enum.filter(agents, fn agent ->
      case status_filter do
        "all" -> true
        "active" -> is_nil(agent.ended_at) || agent.ended_at == ""
        "completed" -> agent.ended_at && agent.ended_at != ""
        _ -> true
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-6 lg:px-8 py-6">
      <div class="max-w-5xl mx-auto">
        <%!-- Search and Filters --%>
        <div class="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-3 flex-1">
            <form phx-change="search" class="flex-1 max-w-sm">
              <label for="search" class="sr-only">Search sessions</label>
              <div class="relative">
                <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                  <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
                </div>
                <input
                  type="text"
                  name="query"
                  id="search"
                  phx-debounce="300"
                  value={@search_query}
                  class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-sm"
                  placeholder="Search sessions..."
                />
              </div>
            </form>

            <div class="flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
              <button
                phx-click="filter_status"
                phx-value-status="all"
                class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                  if(@status_filter == "all",
                    do: "bg-base-100 text-base-content shadow-sm",
                    else: "text-base-content/40 hover:text-base-content/60"
                  )}
              >
                All
              </button>
              <button
                phx-click="filter_status"
                phx-value-status="active"
                class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                  if(@status_filter == "active",
                    do: "bg-base-100 text-success shadow-sm",
                    else: "text-base-content/40 hover:text-base-content/60"
                  )}
              >
                Active
              </button>
              <button
                phx-click="filter_status"
                phx-value-status="completed"
                class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                  if(@status_filter == "completed",
                    do: "bg-base-100 text-base-content shadow-sm",
                    else: "text-base-content/40 hover:text-base-content/60"
                  )}
              >
                Completed
              </button>
            </div>
          </div>

          <button
            phx-click="toggle_new_session_drawer"
            class="btn btn-sm btn-primary gap-1.5 min-h-0 h-7 text-xs"
          >
            <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Session
          </button>
        </div>

        <%= if length(@agents) > 0 do %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3 bg-[oklch(97%_0.005_80)] dark:bg-[oklch(18%_0.005_260)] rounded-xl shadow-sm p-4">
            <%= for agent <- @agents do %>
              <.session_card session={agent} show_project={false} />
            <% end %>
          </div>
        <% else %>
          <.empty_state
            id="project-sessions-empty"
            icon="hero-clock"
            title={
              if @search_query != "" || @status_filter != "all",
                do: "No sessions match your filters",
                else: "No sessions yet"
            }
            subtitle={
              if @search_query != "" || @status_filter != "all",
                do: "Try adjusting your search or filters",
                else: "Sessions will appear here when agents start working on this project"
            }
          />
        <% end %>
      </div>
    </div>

    <.live_component
      module={EyeInTheSkyWebWeb.Components.NewSessionDrawer}
      id="new-session-drawer-project"
      show={@show_new_session_drawer}
      projects={nil}
      current_project={@project}
      toggle_event="toggle_new_session_drawer"
      submit_event="create_new_session"
    />
    """
  end
end
