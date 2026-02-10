defmodule EyeInTheSkyWebWeb.ProjectLive.Sessions do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Sessions
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

        sessions =
          Sessions.list_session_overview_rows(
            project_id: project_id,
            limit: 50,
            search_query: ""
          )

        socket
        |> assign(:page_title, "Sessions - #{project.name}")
        |> assign(:project, project)
        |> assign(:tasks, tasks)
        |> assign(:search_query, "")
        |> assign(:status_filter, "all")
        |> assign(:sessions, sessions)
        |> assign(:show_new_session_drawer, false)
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:tasks, [])
        |> assign(:search_query, "")
        |> assign(:status_filter, "all")
        |> assign(:sessions, [])
        |> assign(:filtered_sessions, [])
        |> put_flash(:error, "Invalid project ID")
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 4, do: query, else: ""

    project_id = socket.assigns.project.id
    status_filter = socket.assigns.status_filter

    sessions =
      Sessions.list_session_overview_rows(
        project_id: project_id,
        limit: 50,
        search_query: effective_query
      )

    filtered_sessions = apply_status_filter(sessions, status_filter)

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> assign(:sessions, filtered_sessions)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    # Apply status filter to current sessions
    filtered_sessions = apply_status_filter(socket.assigns.sessions, status)

    socket =
      socket
      |> assign(:status_filter, status)
      |> assign(:sessions, filtered_sessions)

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

    prompt = "Start new eits session: session-id #{session_id} agent-id #{agent_id} description: #{description}"

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

  defp apply_status_filter(sessions, status_filter) do
    Enum.filter(sessions, fn session ->
      case status_filter do
        "all" -> true
        "active" -> is_nil(session.ended_at) || session.ended_at == ""
        "completed" -> session.ended_at && session.ended_at != ""
        _ -> true
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={EyeInTheSkyWebWeb.Components.Navbar}
      id="navbar"
      current_project={@project}
    />

    <EyeInTheSkyWebWeb.Components.ProjectNav.render
      project={@project}
      tasks={@tasks}
      current_tab={:agents}
    />

    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <!-- Search and Filters -->
        <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:gap-6 flex-1">
            <!-- Search -->
            <div class="flex-1 max-w-md">
              <form phx-change="search">
                <label for="search" class="sr-only">Search sessions</label>
                <div class="relative">
                  <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                    <svg class="h-5 w-5 text-base-content/40" viewBox="0 0 20 20" fill="currentColor">
                      <path
                        fill-rule="evenodd"
                        d="M9 3.5a5.5 5.5 0 100 11 5.5 5.5 0 000-11zM2 9a7 7 0 1112.452 4.391l3.328 3.329a.75.75 0 11-1.06 1.06l-3.329-3.328A7 7 0 012 9z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </div>
                  <input
                    type="text"
                    name="query"
                    id="search"
                    phx-debounce="300"
                    value={@search_query}
                    class="input input-bordered w-full pl-10"
                    placeholder="Search sessions, agents, descriptions..."
                  />
                </div>
              </form>
            </div>

            <!-- Status Filter -->
            <div class="btn-group">
              <button
                phx-click="filter_status"
                phx-value-status="all"
                class={"btn btn-sm #{if @status_filter == "all", do: "btn-active"}"}
              >
                All
              </button>
              <button
                phx-click="filter_status"
                phx-value-status="active"
                class={"btn btn-sm #{if @status_filter == "active", do: "btn-active"}"}
              >
                Active
              </button>
              <button
                phx-click="filter_status"
                phx-value-status="completed"
                class={"btn btn-sm #{if @status_filter == "completed", do: "btn-active"}"}
              >
                Completed
              </button>
            </div>
          </div>

          <!-- New Session Button -->
          <button phx-click="toggle_new_session_drawer" class="btn btn-primary btn-sm">
            + New Session
          </button>
        </div>

        <%= if length(@sessions) > 0 do %>
          <!-- Sessions Grid -->
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for session <- @sessions do %>
              <.session_card session={session} show_project={false} />
            <% end %>
          </div>
        <% else %>
          <!-- Empty State -->
          <div class="text-center py-12">
            <svg
              class="mx-auto h-12 w-12 text-base-content/40"
              fill="currentColor"
              viewBox="0 0 16 16"
            >
              <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Zm7-3.25v2.992l2.028.812a.75.75 0 0 1-.557 1.392l-2.5-1A.751.751 0 0 1 7 8.25v-3.5a.75.75 0 0 1 1.5 0Z" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-base-content">
              <%= if @search_query != "" || @status_filter != "all" do %>
                No sessions match your filters
              <% else %>
                No sessions yet
              <% end %>
            </h3>
            <p class="mt-1 text-sm text-base-content/60">
              <%= if @search_query != "" || @status_filter != "all" do %>
                Try adjusting your search or filters
              <% else %>
                Sessions will appear here when agents start working on this project
              <% end %>
            </p>
          </div>
        <% end %>
      </div>
    </div>

    <!-- New Session Drawer -->
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
