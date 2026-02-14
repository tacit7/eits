defmodule EyeInTheSkyWebWeb.AgentLive.Index do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.{Agents, ChatAgents}
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers
  import EyeInTheSkyWebWeb.Components.Icons

  @default_refresh_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agents")
    end

    projects = EyeInTheSkyWeb.Projects.list_projects()

    socket =
      socket
      |> assign(:page_title, "Eye in the Sky - Agents")
      |> assign(:search_query, "")
      |> assign(:sort_by, "recent")
      |> assign(:session_filter, "all")
      |> assign(:agents, [])
      |> assign(:show_new_session_drawer, false)
      |> assign(:projects, projects)
      |> assign(:refresh_interval, @default_refresh_ms)
      |> assign(:timer_ref, nil)
      |> assign(:refresh_tick, 0)
      |> load_agents()
      |> schedule_refresh()

    {:ok, socket}
  end

  defp load_agents(socket) do
    db_agents = Agents.list_agents_with_chat_agent(include_archived: false)

    # Build project lookup map from assigns
    project_map =
      socket.assigns.projects
      |> Enum.into(%{}, fn p -> {p.id, p.name} end)

    agents =
      db_agents
      |> Enum.map(fn s -> Map.put(s, :project_name, project_map[s.project_id]) end)
      |> filter_agents_by_status(socket.assigns.session_filter)
      |> filter_agents_by_search(socket.assigns.search_query)
      |> sort_agents(socket.assigns.sort_by)

    assign(socket, :agents, agents)
  end

  defp filter_agents_by_status(sessions, filter) do
    case filter do
      "active" ->
        Enum.filter(sessions, &(&1.status in ["active", "working", nil] and is_nil(&1.archived_at)))

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
          [
            s.uuid,
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

  defp sort_agents(sessions, sort_by) do
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

  defp session_status_rank(agent) do
    case agent.status do
      "discovered" -> 0
      "working" -> 1
      "active" -> 1
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
          with {:ok, agent} <- Agents.get_execution_agent(target_session_id),
               {:ok, chat_agent} <- ChatAgents.get_chat_agent(agent.agent_id) do
            project_path = chat_agent.git_worktree_path || File.cwd!()

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
  def handle_event("archive_session", %{"session_id" => session_id}, socket) do
    require Logger
    Logger.info("🗄️  Archive button clicked for session: #{session_id}")

    with {:ok, agent} <- Agents.get_execution_agent(session_id),
         {:ok, updated} <- Agents.archive_execution_agent(agent) do
      Logger.info("✅ Session archived successfully: #{session_id}, archived_at now: #{inspect(updated.archived_at)}")

      socket =
        socket
        |> load_agents()
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

    with {:ok, agent} <- Agents.get_execution_agent(session_id),
         {:ok, updated} <- Agents.unarchive_execution_agent(agent) do
      Logger.info("✅ Session unarchived successfully: #{session_id}, archived_at now: #{inspect(updated.archived_at)}")

      socket =
        socket
        |> load_agents()
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
    with {:ok, agent} <- Agents.get_execution_agent(session_id),
         {:ok, _} <- Agents.delete_execution_agent(agent) do
      socket =
        socket
        |> load_agents()
        |> put_flash(:info, "Session deleted successfully")

      {:noreply, socket}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete session")}
    end
  end

  @impl true
  def handle_event("navigate_dm", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dm/#{id}")}
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_refresh", %{"interval" => interval}, socket) do
    socket = cancel_timer(socket)

    case Integer.parse(interval) do
      {ms, _} when ms > 0 ->
        {:noreply, socket |> assign(:refresh_interval, ms) |> schedule_refresh()}

      _ ->
        {:noreply, assign(socket, refresh_interval: nil, timer_ref: nil)}
    end
  end

  @impl true
  def handle_info(:refresh_agents, socket) do
    tick = socket.assigns.refresh_tick + 1
    socket = socket |> assign(:refresh_tick, tick) |> load_agents() |> schedule_refresh()
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_new_session_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_session_drawer, !socket.assigns.show_new_session_drawer)}
  end

  @impl true
  def handle_event("create_new_session", params, socket) do
    require Logger

    model = params["model"]
    effort_level = params["effort_level"]
    project_id = String.to_integer(params["project_id"])
    description = params["description"]
    agent_name = params["agent_name"]

    project = EyeInTheSkyWeb.Projects.get_project!(project_id)

    opts = [
      model: model,
      effort_level: effort_level,
      project_id: project_id,
      project_path: project.path,
      description: agent_name || description,
      instructions: description
    ]

    Logger.info("🚀 create_new_session: model=#{model}, effort=#{inspect(effort_level)}, project_id=#{project_id}, project_path=#{project.path}")

    case EyeInTheSkyWeb.Claude.SessionManager.create_agent(opts) do
      {:ok, result} ->
        Logger.info("✅ create_new_session: agent created - agent_id=#{result.agent.id}, session_id=#{result.agent.id}, session_uuid=#{result.agent.uuid}")

        socket =
          socket
          |> assign(:show_new_session_drawer, false)
          |> load_agents()
          |> put_flash(:info, "Session launched")

        Logger.info("📤 create_new_session: returning success response to client, closing drawer, reloading sessions")
        {:noreply, socket}

      {:error, reason} ->
        Logger.error("❌ create_new_session: failed - #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:agent_updated, _agent}, socket) do
    {:noreply, load_agents(socket)}
  end

  @impl true
  def handle_info({:claude_output, _ref, _line}, socket) do
    # Ignore Claude output - SessionWorker handles these
    {:noreply, socket}
  end

  @impl true
  def handle_info({:claude_exit, _ref, _status}, socket) do
    # Ignore Claude exit - SessionWorker handles these
    {:noreply, socket}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Agents")
  end

  defp schedule_refresh(%{assigns: %{refresh_interval: nil}} = socket), do: socket

  defp schedule_refresh(%{assigns: %{refresh_interval: ms}} = socket) do
    socket = cancel_timer(socket)
    ref = Process.send_after(self(), :refresh_agents, ms)
    assign(socket, :timer_ref, ref)
  end

  defp cancel_timer(%{assigns: %{timer_ref: ref}} = socket) when is_reference(ref) do
    Process.cancel_timer(ref)
    assign(socket, :timer_ref, nil)
  end

  defp cancel_timer(socket), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={EyeInTheSkyWebWeb.Components.Navbar} id="navbar" />
    <EyeInTheSkyWebWeb.Components.OverviewNav.render current_tab={:sessions} />
    <Layouts.flash_group flash={@flash} />
    <div class="px-6 lg:px-8">
      <div class="max-w-3xl mx-auto">
        <!-- Page Header -->
        <div class="flex items-start justify-between py-6 border-b border-base-content/10">
          <div class="flex-1"></div>
          <div class="flex items-center gap-2 flex-shrink-0">
            <%= if @refresh_interval do %>
              <span
                id="refresh-dot"
                phx-hook="RefreshDot"
                data-tick={@refresh_tick}
                class="inline-flex h-2 w-2 rounded-full bg-success opacity-0 transition-opacity duration-300"
              ></span>
            <% end %>
            <span class="text-xs text-base-content/50">Update every</span>
            <select phx-change="set_refresh" name="interval" class="select select-xs select-bordered w-20">
              <option value="0" selected={@refresh_interval == nil}>Off</option>
              <option value="1000" selected={@refresh_interval == 1000}>1s</option>
              <option value="5000" selected={@refresh_interval == 5000}>5s</option>
              <option value="15000" selected={@refresh_interval == 15000}>15s</option>
              <option value="30000" selected={@refresh_interval == 30000}>30s</option>
              <option value="60000" selected={@refresh_interval == 60000}>1m</option>
            </select>
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
          <form phx-submit="search" phx-change="search" class="flex-1 max-w-md flex gap-2">
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
                phx-debounce="300"
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
              <h3 class="text-sm font-medium text-base-content">No sessions found</h3>
              <p class="mt-1 text-sm text-base-content/60">Try adjusting your search or filters</p>
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-xs table-zebra">
                <tbody>
                  <%= for agent <- @agents do %>
                    <% {status_color, status_label} =
                      case agent.status do
                        "working" -> {"text-orange-500", "Working"}
                        "completed" -> {"text-red-500", "Stale"}
                        "discovered" -> {"text-green-500", "Waiting"}
                        _ -> {"text-green-500", "Waiting"}
                      end %>
                    <tr class="hover cursor-pointer group" phx-click="navigate_dm" phx-value-id={agent.id}>
                      <td class="py-2">
                        <.link navigate={~p"/dm/#{agent.id}"} class="font-mono text-sm text-primary hover:underline" onclick="event.stopPropagation()">
                          #{agent.id}
                        </.link>
                      </td>
                      <td class="py-2" phx-click="noop">
                        <div class="flex items-center gap-0 opacity-0 group-hover:opacity-100 transition-opacity">
                          <%= if agent.id do %>
                            <a href={~p"/dm/#{agent.id}"} target="_blank" class="btn btn-ghost btn-xs btn-square" aria-label="Open DM">
                              <.arrow_top_right_on_square class="w-3.5 h-3.5" />
                            </a>
                          <% end %>
                          <%= if agent.chat_agent.uuid && agent.uuid do %>
                            <button
                              id={"bookmark-btn-#{agent.uuid}"}
                              type="button"
                              phx-hook="BookmarkAgent"
                              data-agent-id={agent.chat_agent.uuid}
                              data-session-id={agent.uuid}
                              data-agent-name={agent.name || agent.chat_agent.description || "Agent"}
                              data-agent-status={agent.status}
                              class="bookmark-button btn btn-ghost btn-xs btn-square"
                              aria-label="Bookmark agent"
                            >
                              <.heart class="bookmark-icon w-3.5 h-3.5" />
                            </button>
                          <% end %>
                          <%= if agent.uuid do %>
                            <%= if agent.archived_at do %>
                              <button type="button" phx-click="unarchive_session" phx-value-session_id={agent.id} class="btn btn-ghost btn-xs btn-square" aria-label="Unarchive">
                                <.icon name="hero-arrow-up-tray" class="size-3.5" />
                              </button>
                            <% else %>
                              <button type="button" phx-click="archive_session" phx-value-session_id={agent.id} class="btn btn-ghost btn-xs btn-square" aria-label="Archive">
                                <.archive_box class="w-3.5 h-3.5" />
                              </button>
                            <% end %>
                          <% end %>
                        </div>
                      </td>
                      <td class="py-2" title={status_label}>
                        <div class="flex items-center gap-1.5">
                          <.claude class={"w-3.5 h-3.5 " <> status_color} />
                          <span class={"text-xs " <> status_color}>{status_label}</span>
                        </div>
                      </td>
                      <td class="py-2">
                        <div class="text-sm">{agent.name || "Unnamed session"}</div>
                        <div class="flex items-center gap-2 text-xs text-base-content/40 mt-1.5">
                          <span class="font-mono">{Agents.format_model_info(agent)}</span>
                          <%= if agent.project_name do %>
                            <span>&middot;</span>
                            <span>{agent.project_name}</span>
                          <% end %>
                          <span>&middot;</span>
                          <span>{relative_time(agent.started_at)}</span>
                        </div>
                      </td>
                      <td class="py-2 text-xs text-base-content/50 truncate max-w-xs">{agent.chat_agent.description}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <!-- New Session Drawer -->
    <.live_component
      module={EyeInTheSkyWebWeb.Components.NewSessionDrawer}
      id="new-session-drawer"
      show={@show_new_session_drawer}
      projects={@projects}
      current_project={nil}
      toggle_event="toggle_new_session_drawer"
      submit_event="create_new_session"
    />
    """
  end
end
