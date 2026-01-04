defmodule EyeInTheSkyWebWeb.AgentLive.Index do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Sessions
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers
  import EyeInTheSkyWebWeb.Components.Icons

  @refresh_interval_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to agent updates if connected
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agents")
      # Refresh agents list every 30 seconds (less aggressive)
      :timer.send_interval(@refresh_interval_ms, self(), :refresh_agents)
    end

    projects = EyeInTheSkyWeb.Projects.list_projects()

    socket =
      socket
      |> assign(:page_title, "Eye in the Sky - Agents")
      |> assign(:search_query, "")
      |> assign(:sort_by, "recent")
      |> assign(:session_filter, "all")
      |> assign(:sessions, [])
      |> assign(:show_new_session_drawer, false)
      |> assign(:projects, projects)
      |> load_sessions()

    {:ok, socket}
  end

  defp load_sessions(socket) do
    db_sessions = Sessions.list_sessions_with_agent(include_archived: false)

    sessions =
      db_sessions
      |> filter_sessions_by_status(socket.assigns.session_filter)
      |> filter_sessions_by_search(socket.assigns.search_query)
      |> sort_sessions(socket.assigns.sort_by)

    assign(socket, :sessions, sessions)
  end

  defp filter_sessions_by_status(sessions, filter) do
    case filter do
      "active" ->
        Enum.filter(sessions, &(is_nil(&1.ended_at) and is_nil(&1.archived_at)))

      "completed" ->
        Enum.filter(sessions, &(!is_nil(&1.ended_at) and is_nil(&1.archived_at)))

      "archived" ->
        Enum.filter(sessions, &(!is_nil(&1.archived_at)))

      _ ->
        sessions
    end
  end

  defp filter_sessions_by_search(sessions, query) do
    q = (query || "") |> String.trim() |> String.downcase()

    if q == "" do
      sessions
    else
      Enum.filter(sessions, fn s ->
        haystack =
          [
            s.id,
            s.name,
            s.agent.description,
            s.agent.project_name
          ]
          |> Enum.map(&to_string_or_empty/1)
          |> Enum.join(" ")
          |> String.downcase()

        String.contains?(haystack, q)
      end)
    end
  end

  defp sort_sessions(sessions, sort_by) do
    case sort_by do
      "name" ->
        Enum.sort_by(sessions, fn s -> (s.name || "") |> String.downcase() end)

      "status" ->
        Enum.sort_by(sessions, fn s -> session_status_rank(s) end)

      _ ->
        # "recent" (default)
        Enum.sort_by(sessions, fn s -> sort_datetime(s.started_at) end, {:desc, NaiveDateTime})
    end
  end

  defp session_status_rank(session) do
    cond do
      get_in(session, [:agent, :status]) == "discovered" -> 0
      is_nil(session.ended_at) -> 1
      true -> 2
    end
  end

  defp to_string_or_empty(nil), do: ""
  defp to_string_or_empty(v) when is_binary(v), do: v
  defp to_string_or_empty(v), do: to_string(v)

  defp sort_datetime(%NaiveDateTime{} = ndt), do: ndt
  defp sort_datetime(%DateTime{} = dt), do: DateTime.to_naive(dt)
  defp sort_datetime(_), do: ~N[0000-01-01 00:00:00]

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event(
        "send_direct_message",
        %{"session_id" => target_session_id, "body" => body},
        socket
      ) do
    # Get the global channel for this project
    # Default project
    project_id = 1
    channels = EyeInTheSkyWeb.Channels.list_channels_for_project(project_id)
    global_channel = Enum.find(channels, fn c -> c.name == "#global" end)

    if global_channel do
      # Send message via the chat system
      case EyeInTheSkyWeb.Messages.send_channel_message(%{
             channel_id: global_channel.id,
             session_id: "web-user",
             sender_role: "user",
             recipient_role: "agent",
             provider: "claude",
             body: body
           }) do
        {:ok, message} ->
          # Broadcast to channel
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "channel:#{global_channel.id}:messages",
            {:new_message, message}
          )

          # Continue the agent's session
          with {:ok, session} <- EyeInTheSkyWeb.Sessions.get_session(target_session_id),
               {:ok, agent} <- EyeInTheSkyWeb.Agents.get_agent(session.agent_id) do
            project_path = agent.git_worktree_path || File.cwd!()

            prompt_with_reminder = """
            REMINDER: Use i-chat-send MCP tool to send your response to the channel.

            User message: #{body}
            """

            EyeInTheSkyWeb.Claude.SessionManager.continue_session(
              target_session_id,
              prompt_with_reminder,
              model: "sonnet",
              project_path: project_path
            )
          end

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
    else
      {:noreply, put_flash(socket, :error, "Global channel not found")}
    end
  end

  @impl true
  def handle_event("open_chat", %{"session_id" => _session_id}, socket) do
    # Navigate to agent detail view - currently no dedicated session view
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> load_sessions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_session", %{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:session_filter, filter)
      |> load_sessions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"by" => sort_by}, socket) do
    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> load_sessions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("archive_session", %{"session_id" => session_id}, socket) do
    require Logger
    Logger.info("🗄️  Archive button clicked for session: #{session_id}")

    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, updated} <- Sessions.archive_session(session) do
      Logger.info("✅ Session archived successfully: #{session_id}, archived_at now: #{inspect(updated.archived_at)}")

      socket =
        socket
        |> load_sessions()
        |> put_flash(:info, "Session archived successfully")

      {:noreply, socket}
    else
      {:error, reason} ->
        Logger.error("❌ Failed to archive session #{session_id}: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to archive session")}
    end
  end

  @impl true
  def handle_event("unarchive_session", %{"session_id" => session_id}, socket) do
    require Logger
    Logger.info("🔄 Unarchive button clicked for session: #{session_id}")

    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, updated} <- Sessions.unarchive_session(session) do
      Logger.info("✅ Session unarchived successfully: #{session_id}, archived_at now: #{inspect(updated.archived_at)}")

      socket =
        socket
        |> load_sessions()
        |> put_flash(:info, "Session unarchived successfully")

      {:noreply, socket}
    else
      {:error, reason} ->
        Logger.error("❌ Failed to unarchive session #{session_id}: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to unarchive session")}
    end
  end

  @impl true
  def handle_event("delete_session", %{"session_id" => session_id}, socket) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.delete_session(session) do
      socket =
        socket
        |> load_sessions()
        |> put_flash(:info, "Session deleted successfully")

      {:noreply, socket}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete session")}
    end
  end

  @impl true
  def handle_info(:refresh_agents, socket) do
    {:noreply, load_sessions(socket)}
  end

  @impl true
  def handle_event("toggle_new_session_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_session_drawer, !socket.assigns.show_new_session_drawer)}
  end

  @impl true
  def handle_event("create_new_session", params, socket) do
    # Extract form data
    model = params["model"]
    project_id = String.to_integer(params["project_id"])
    agent_name = params["agent_name"]
    description = params["description"]

    # Get project for git path
    project = EyeInTheSkyWeb.Projects.get_project!(project_id)

    # Generate UUIDs
    session_id = Ecto.UUID.generate()
    agent_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    # Create agent
    case EyeInTheSkyWeb.Agents.create_agent(%{
           id: agent_id,
           name: agent_name,
           description: description,
           project_id: project_id,
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

  @impl true
  def handle_info({:agent_updated, _agent}, socket) do
    {:noreply, load_sessions(socket)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Agents")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={EyeInTheSkyWebWeb.Components.Navbar} id="navbar" />
    <div class="px-6 lg:px-8">
      <div class="max-w-7xl mx-auto">
        <!-- Page Header -->
        <div class="flex items-start justify-between py-6 border-b border-base-content/10">
          <div class="flex-1">
            <h1 class="text-2xl font-semibold text-base-content">Agents</h1>
            <p class="mt-1 text-sm text-base-content/60">
              Real-time overview of all Claude Code agents
            </p>
          </div>
          <div class="flex items-center gap-2 flex-shrink-0">
            <button phx-click="toggle_new_session_drawer" class="btn btn-primary btn-sm">
              + New Session
            </button>
            <label class="swap swap-rotate btn btn-ghost btn-sm btn-circle">
              <input type="checkbox" class="theme-controller" value="dark" />
              <svg class="swap-on h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"
                />
              </svg>
              <svg class="swap-off h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z"
                />
              </svg>
            </label>
          </div>
        </div>
        
    <!-- Search and Filters Toolbar -->
        <div class="sticky top-16 z-10 bg-base-100/80 backdrop-blur border-b border-base-content/10 -mx-6 lg:-mx-8 px-6 lg:px-8 py-4 my-4 flex flex-col gap-4 sm:flex-row sm:items-center sm:gap-4">
          <!-- Search -->
          <form phx-submit="search" class="flex-1 max-w-md flex gap-2">
            <label for="search" class="sr-only">Search sessions</label>
            <div class="relative flex-1">
              <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <svg class="h-5 w-5 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
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
                value={@search_query}
                class="input input-bordered w-full pl-10"
                placeholder="Search sessions, projects, descriptions..."
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Search</button>
          </form>
          
    <!-- Session Status Filter -->
          <div class="btn-group">
            <button
              phx-click="filter_session"
              phx-value-filter="all"
              class={"btn btn-sm #{if @session_filter == "all", do: "btn-active"}"}
            >
              All
            </button>
            <button
              phx-click="filter_session"
              phx-value-filter="active"
              class={"btn btn-sm #{if @session_filter == "active", do: "btn-active"}"}
            >
              Active
            </button>
            <button
              phx-click="filter_session"
              phx-value-filter="completed"
              class={"btn btn-sm #{if @session_filter == "completed", do: "btn-active"}"}
            >
              Completed
            </button>
          </div>
        </div>

        <div class="mt-6">
          <%= if @sessions == [] do %>
            <div class="text-center py-12">
              <svg
                class="mx-auto h-12 w-12 text-base-content/40"
                fill="currentColor"
                viewBox="0 0 16 16"
              >
                <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Zm7-3.25v2.992l2.028.812a.75.75 0 0 1-.557 1.392l-2.5-1A.751.751 0 0 1 7 8.25v-3.5a.75.75 0 0 1 1.5 0Z" />
              </svg>
              <h3 class="mt-2 text-sm font-medium text-base-content">No sessions found</h3>
              <p class="mt-1 text-sm text-base-content/60">Try adjusting your search or filters</p>
            </div>
          <% else %>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
              <%= for session <- @sessions do %>
                <div class="card bg-base-100 border border-base-300 hover:border-base-300 transition-all h-full relative">
                  <div class="card-body p-3">
                    <!-- Title Row with Actions -->
                    <div class="flex items-start justify-between gap-2 mb-2">
                      <div class="flex-1 min-w-0">
                        <!-- Session ID and Status -->
                        <div class="flex items-center gap-3 mb-2">
                          <.link
                            navigate={~p"/agents/#{session.agent.id}"}
                            class="text-sm font-mono text-primary hover:text-primary-focus font-semibold hover:underline"
                          >
                            {String.slice(session.id, 0..7)}
                          </.link>
                            <% status_badge =
                              case {session.status, session.ended_at} do
                                {"discovered", _} ->
                                  %{text: "Discovered", class: "badge badge-info badge-sm"}

                                {_, nil} ->
                                  %{text: "Active", class: "badge badge-success badge-sm"}

                                _ ->
                                  %{text: "Completed", class: "badge badge-ghost badge-sm"}
                              end %>
                            <span class={status_badge.class}>
                              {status_badge.text}
                            </span>
                          </div>
                          
    <!-- Session Name -->
                          <h3 class="text-sm font-medium text-base-content mb-2 line-clamp-2">
                            {session.name || "Unnamed session"}
                          </h3>
                        </div>
                        
    <!-- Action Buttons -->
                        <div class="flex items-center gap-1 flex-shrink-0">
                          <%= if session.id do %>
                            <a
                              href={~p"/dm/#{session.id}"}
                              target="_blank"
                              class="btn btn-ghost btn-xs text-base-content/40 hover:text-info transition-colors"
                              aria-label="Open DM window"
                              onclick="event.stopPropagation()"
                            >
                              <.arrow_top_right_on_square class="w-4 h-4 text-base-content/60" />
                            </a>
                          <% end %>
                          <%= if session.agent.id && session.id do %>
                            <button
                              id={"bookmark-btn-#{session.id}"}
                              type="button"
                              phx-hook="BookmarkAgent"
                              data-agent-id={session.agent.id}
                              data-session-id={session.id}
                              data-agent-name={session.name || session.agent.description || "Agent"}
                              data-agent-status={session.status}
                              class="bookmark-button btn btn-ghost btn-xs text-base-content/40 hover:text-warning transition-colors"
                              onclick="event.stopPropagation()"
                              aria-label="Bookmark agent"
                            >
                              <.heart class="bookmark-icon w-4 h-4 text-base-content/60" />
                            </button>
                          <% end %>
                          <%= if session.id do %>
                            <%= if session.archived_at do %>
                              <button
                                type="button"
                                phx-click="unarchive_session"
                                phx-value-session_id={session.id}
                                class="btn btn-ghost btn-xs text-base-content/40 hover:text-success transition-colors"
                                aria-label="Unarchive session"
                                onclick="event.stopPropagation()"
                              >
                                <svg class="w-4 h-4 text-base-content/60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"/>
                                </svg>
                              </button>
                            <% else %>
                              <button
                                type="button"
                                phx-click="archive_session"
                                phx-value-session_id={session.id}
                                phx-capture-click="true"
                                class="btn btn-ghost btn-xs text-base-content/40 hover:text-warning transition-colors"
                                aria-label="Archive session"
                              >
                                <.archive_box class="w-4 h-4 text-base-content/60" />
                              </button>
                            <% end %>
                          <% end %>
                        </div>
                      </div>
                      
    <!-- Description -->
                      <%= if session.agent.description do %>
                        <p class="text-xs text-base-content/70 mb-2 line-clamp-2">
                          {session.agent.description}
                        </p>
                      <% end %>
                      
    <!-- Meta Information -->
                      <div class="flex items-center gap-4 text-xs text-base-content/60">
                        <%= if session.agent.project_name do %>
                          <span class="flex items-center gap-1">
                            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 16 16">
                              <path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75Z" />
                            </svg>
                            {session.agent.project_name}
                          </span>
                        <% end %>
                        <span class="flex items-center gap-1 font-mono text-xs text-base-content/70">
                          <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 16 16">
                            <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Z" />
                          </svg>
                          {Sessions.format_model_info(session)}
                        </span>
                        <span class="flex items-center gap-1">
                          <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 16 16">
                            <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Z" />
                          </svg>
                          {relative_time(session.started_at)}
                        </span>
                      </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
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

            <!-- Project Selection -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Project</span>
              </label>
              <select name="project_id" class="select select-bordered" required>
                <option value="">Select a project...</option>
                <%= for project <- @projects do %>
                  <option value={project.id}><%= project.name %></option>
                <% end %>
              </select>
              <label class="label">
                <span class="label-text-alt">Sets the working directory for Claude Code</span>
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
end
