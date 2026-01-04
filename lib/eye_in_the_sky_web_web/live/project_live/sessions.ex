defmodule EyeInTheSkyWebWeb.ProjectLive.Sessions do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Repo

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

        filtered_agents =
          filter_agents(%{
            project: project,
            search_query: "",
            status_filter: "active"
          })

        socket
        |> assign(:page_title, "Agents - #{project.name}")
        |> assign(:project, project)
        |> assign(:tasks, tasks)
        |> assign(:search_query, "")
        |> assign(:status_filter, "active")
        |> assign(:filtered_agents, filtered_agents)
        |> assign(:show_new_session_drawer, false)
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:tasks, [])
        |> assign(:search_query, "")
        |> assign(:status_filter, "active")
        |> assign(:filtered_agents, [])
        |> put_flash(:error, "Invalid project ID")
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> update_filtered_agents()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    socket =
      socket
      |> assign(:status_filter, status)
      |> update_filtered_agents()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_new_session_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_session_drawer, !socket.assigns.show_new_session_drawer)}
  end

  @impl true
  def handle_event("create_new_session", params, socket) do
    alias EyeInTheSkyWeb.{Sessions, Agents}

    # Extract form data
    model = params["model"]
    agent_name = params["agent_name"]
    description = params["description"]

    # Use current project
    project = socket.assigns.project

    # Generate UUIDs
    session_id = Ecto.UUID.generate()
    agent_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    # Create agent
    case Agents.create_agent(%{
           id: agent_id,
           name: agent_name,
           description: description,
           project_id: project.id,
           git_worktree_path: project.path
         }) do
      {:ok, _agent} ->
        # Create session
        case Sessions.create_session_with_model(%{
               id: session_id,
               agent_id: agent_id,
               name: agent_name,
               description: description,
               started_at: now,
               model_provider: "claude",
               model_name: model
             }) do
          {:ok, _session} ->
            socket =
              socket
              |> assign(:show_new_session_drawer, false)
              |> put_flash(:info, "Session created successfully")
              |> push_navigate(to: ~p"/agents/#{agent_id}")

            {:noreply, socket}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(changeset.errors)}")}
        end

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create agent: #{inspect(changeset.errors)}")}
    end
  end

  defp update_filtered_agents(socket) do
    filtered = filter_agents(socket.assigns)
    assign(socket, :filtered_agents, filtered)
  end

  defp filter_agents(assigns) do
    agents = assigns.project.agents
    query = String.downcase(assigns.search_query)
    status_filter = assigns.status_filter

    agents
    |> Enum.filter(fn agent ->
      # Search filter
      search_match =
        if query == "" do
          true
        else
          String.contains?(String.downcase(agent.id || ""), query) ||
            String.contains?(String.downcase(agent.description || ""), query) ||
            String.contains?(String.downcase(agent.feature_description || ""), query) ||
            String.contains?(String.downcase(agent.session_id || ""), query)
        end

      # Status filter
      status_match =
        case status_filter do
          "all" -> true
          status -> get_agent_status(agent) == status
        end

      search_match && status_match
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
              <label for="search" class="sr-only">Search agents</label>
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
                  placeholder="Search agents, sessions, descriptions..."
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
              phx-value-status="working"
              class={"btn btn-sm #{if @status_filter == "working", do: "btn-active"}"}
            >
              Working
            </button>
            <button
              phx-click="filter_status"
              phx-value-status="idle"
              class={"btn btn-sm #{if @status_filter == "idle", do: "btn-active"}"}
            >
              Idle
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

        <%= if length(@filtered_agents) > 0 do %>
          <!-- Agents List -->
          <div class="space-y-4">
            <%= for agent <- @filtered_agents do %>
              <a href={"/agents/#{agent.id}"} class="block">
                <div class="card bg-base-100 border border-base-300 hover:border-primary hover:shadow-md transition-all">
                  <div class="card-body">
                    <div class="flex items-start justify-between">
                      <div class="flex-1 min-w-0">
                        <!-- Agent ID and Status -->
                        <div class="flex items-center gap-3 mb-2">
                          <code class="text-sm font-mono text-base-content font-semibold">
                            {String.slice(agent.id, 0..7)}
                          </code>
                          <span class={"badge badge-sm #{status_badge_class(get_agent_status(agent))}"}>
                            {get_agent_status(agent)}
                          </span>
                        </div>
                        
    <!-- Description -->
                        <%= if agent.feature_description || agent.description do %>
                          <p class="text-sm text-base-content/80 mb-2">
                            {agent.feature_description || agent.description}
                          </p>
                        <% end %>
                        
    <!-- Meta Information -->
                        <div class="flex items-center gap-4 text-xs text-base-content/60">
                          <%= if agent.session_id do %>
                            <span class="flex items-center gap-1">
                              <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 16 16">
                                <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Z" />
                              </svg>
                              Session: {String.slice(agent.session_id, 0..7)}
                            </span>
                          <% end %>
                          <%= if agent.git_worktree_path do %>
                            <span class="flex items-center gap-1 font-mono">
                              <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 16 16">
                                <path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75Z" />
                              </svg>
                              {Path.basename(agent.git_worktree_path)}
                            </span>
                          <% end %>
                        </div>
                      </div>
                      
    <!-- Chevron -->
                      <svg
                        class="w-5 h-5 text-base-content/40 flex-shrink-0 mt-1"
                        fill="currentColor"
                        viewBox="0 0 20 20"
                      >
                        <path
                          fill-rule="evenodd"
                          d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
                          clip-rule="evenodd"
                        />
                      </svg>
                    </div>
                  </div>
                </div>
              </a>
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
                No agents match your filters
              <% else %>
                No agents yet
              <% end %>
            </h3>
            <p class="mt-1 text-sm text-base-content/60">
              <%= if @search_query != "" || @status_filter != "all" do %>
                Try adjusting your search or filters
              <% else %>
                Agents will appear here when they start working on this project
              <% end %>
            </p>
          </div>
        <% end %>
      </div>
    </div>

    <!-- New Session Drawer -->
    <div class="drawer drawer-end">
      <input
        id="new-session-drawer"
        type="checkbox"
        class="drawer-toggle"
        checked={@show_new_session_drawer}
        phx-click="toggle_new_session_drawer"
      />
      <div class="drawer-side z-50">
        <label for="new-session-drawer" class="drawer-overlay"></label>
        <div class="menu p-6 w-96 min-h-full bg-base-100 text-base-content">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-xl font-semibold">New Session</h2>
            <button phx-click="toggle_new_session_drawer" class="btn btn-ghost btn-sm btn-circle">✕</button>
          </div>

          <form phx-submit="create_new_session" class="flex flex-col gap-4">
            <!-- Model Selection -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Model</span>
              </label>
              <select name="model" class="select select-bordered" required>
                <option value="sonnet">Sonnet</option>
                <option value="haiku">Haiku</option>
                <option value="opus">Opus</option>
              </select>
            </div>

            <!-- Project (read-only) -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Project</span>
              </label>
              <input
                type="text"
                value={@project.name}
                class="input input-bordered"
                disabled
              />
              <label class="label">
                <span class="label-text-alt">Working directory: <%= @project.path %></span>
              </label>
            </div>

            <!-- Agent Name -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Agent Name</span>
              </label>
              <input
                type="text"
                name="agent_name"
                class="input input-bordered"
                placeholder="e.g., Frontend Dev Agent"
                required
              />
            </div>

            <!-- Description -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Description</span>
              </label>
              <textarea
                name="description"
                class="textarea textarea-bordered h-24"
                placeholder="What will this session work on?"
                required
              ></textarea>
            </div>

            <!-- Actions -->
            <div class="flex gap-2 mt-4">
              <button type="submit" class="btn btn-primary flex-1">Create Session</button>
              <button type="button" phx-click="toggle_new_session_drawer" class="btn btn-ghost">Cancel</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp get_agent_status(_agent) do
    # Agents now get their status from their sessions
    # For display purposes, return nil if no active session
    nil
  end

  defp status_badge_class(status) do
    case status do
      "active" -> "badge-success"
      "working" -> "badge-warning"
      "idle" -> "badge-info"
      "completed" -> "badge-ghost"
      "failed" -> "badge-error"
      nil -> "badge-ghost"
      _ -> "badge-ghost"
    end
  end
end
