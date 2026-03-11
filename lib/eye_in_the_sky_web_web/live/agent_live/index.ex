defmodule EyeInTheSkyWebWeb.AgentLive.Index do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Agents
  alias EyeInTheSkyWeb.Claude.{SDK, Message}
  alias EyeInTheSkyWeb.Sessions
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers
  import EyeInTheSkyWebWeb.Components.Icons

  @default_refresh_ms 300_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agents")
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
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
      |> assign(:timer_ref, nil)
      |> assign(:show_sdk_demo, false)
      |> assign(:sdk_ref, nil)
      |> assign(:sdk_messages, [])
      |> assign(:sdk_session_id, nil)
      |> assign(:sdk_prompt, "")
      |> assign(:sidebar_tab, :sessions)
      |> assign(:sidebar_project, nil)
      |> assign(:selected_ids, MapSet.new())
      |> load_agents()
      |> schedule_refresh()

    {:ok, socket}
  end

  defp load_agents(socket) do
    include_archived = socket.assigns.session_filter == "archived"
    db_agents = Sessions.list_sessions_with_agent(include_archived: include_archived)

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
        Enum.filter(
          sessions,
          &(&1.status in ["working", "idle", nil] and is_nil(&1.archived_at))
        )

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
        # "recent" (default) - sort by last_activity_at, fall back to started_at
        Enum.sort_by(
          sessions,
          fn s -> sort_datetime(s.last_activity_at || s.started_at) end,
          {:desc, NaiveDateTime}
        )
    end
  end

  defp session_status_rank(agent) do
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
    # Get the global channel — try agent's project first, fall back to all channels
    project_id =
      case Sessions.get_session(target_session_id) do
        {:ok, agent} -> agent.project_id
        _ -> nil
      end

    channels =
      if project_id,
        do: EyeInTheSkyWeb.Channels.list_channels_for_project(project_id),
        else: EyeInTheSkyWeb.Channels.list_channels()

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
        {:ok, _message} ->
          # Continue the agent's session
          with {:ok, agent} <- Sessions.get_session(target_session_id),
               {:ok, chat_agent} <- Agents.get_agent(agent.agent_id) do
            project_path = chat_agent.git_worktree_path || File.cwd!()

            prompt_with_reminder = """
            REMINDER: Use i-chat-send MCP tool to send your response to the channel.

            User message: #{body}
            """

            EyeInTheSkyWeb.Claude.AgentManager.continue_session(
              agent.id,
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
  def handle_event("archive_session", %{"session_id" => session_id}, socket) do
    require Logger
    Logger.info("🗄️  Archive button clicked for session: #{session_id}")

    with {:ok, agent} <- Sessions.get_session(session_id),
         {:ok, updated} <- Sessions.archive_session(agent) do
      Logger.info(
        "✅ Session archived successfully: #{session_id}, archived_at now: #{inspect(updated.archived_at)}"
      )

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

    with {:ok, agent} <- Sessions.get_session(session_id),
         {:ok, updated} <- Sessions.unarchive_session(agent) do
      Logger.info(
        "✅ Session unarchived successfully: #{session_id}, archived_at now: #{inspect(updated.archived_at)}"
      )

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
    with {:ok, agent} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.delete_session(agent) do
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
    ids = socket.assigns.selected_ids

    results =
      Enum.map(ids, fn id ->
        with {:ok, agent} <- Sessions.get_session(id),
             {:ok, _} <- Sessions.delete_session(agent) do
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
  def handle_info(:refresh_agents, socket) do
    socket = socket |> load_agents() |> schedule_refresh()
    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_created, _agent}, socket) do
    {:noreply, load_agents(socket)}
  end

  @impl true
  def handle_info({:agent_updated, _agent}, socket) do
    {:noreply, load_agents(socket)}
  end

  @impl true
  def handle_info({:agent_deleted, _agent}, socket) do
    {:noreply, load_agents(socket)}
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
    project_id = String.to_integer(params["project_id"])
    description = params["description"]
    agent_name = params["agent_name"] || String.slice(description || "", 0, 60)

    project = EyeInTheSkyWeb.Projects.get_project!(project_id)

    worktree = case params["worktree"] do
      nil -> nil
      "" -> nil
      v -> String.trim(v)
    end

    opts = [
      agent_type: agent_type,
      model: model,
      effort_level: effort_level,
      project_id: project_id,
      project_path: project.path,
      description: agent_name,
      instructions: description,
      worktree: worktree
    ]

    Logger.info(
      "🚀 create_new_session: model=#{model}, effort=#{inspect(effort_level)}, project_id=#{project_id}, project_path=#{project.path}"
    )

    case EyeInTheSkyWeb.Claude.AgentManager.create_agent(opts) do
      {:ok, result} ->
        Logger.info(
          "✅ create_new_session: agent created - agent_id=#{result.agent.id}, session_id=#{result.agent.id}, session_uuid=#{result.agent.uuid}"
        )

        socket =
          socket
          |> assign(:show_new_session_drawer, false)
          |> load_agents()
          |> put_flash(:info, "Session launched")

        Logger.info(
          "📤 create_new_session: returning success response to client, closing drawer, reloading sessions"
        )

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
  def handle_info({:agent_working, %{id: session_id}}, socket) do
    {:noreply, update_agent_status_in_list(socket, session_id, "working")}
  end

  @impl true
  def handle_info({:agent_working, _session_uuid, session_id}, socket) do
    {:noreply, update_agent_status_in_list(socket, session_id, "working")}
  end

  @impl true
  def handle_info({:agent_stopped, %{id: session_id, status: status}}, socket) do
    {:noreply, update_agent_status_in_list(socket, session_id, status || "completed")}
  end

  @impl true
  def handle_info({:agent_stopped, _session_uuid, session_id}, socket) do
    {:noreply, update_agent_status_in_list(socket, session_id, "idle")}
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

  # SDK Demo event handlers
  @impl true
  def handle_event("toggle_sdk_demo", _params, socket) do
    {:noreply, assign(socket, :show_sdk_demo, !socket.assigns.show_sdk_demo)}
  end

  @impl true
  def handle_event("sdk_send_message", %{"prompt" => prompt}, socket) do
    case SDK.start(prompt, to: self(), model: "haiku", max_turns: 1) do
      {:ok, ref} ->
        socket =
          socket
          |> assign(:sdk_ref, ref)
          |> assign(:sdk_prompt, "")
          |> assign(:sdk_messages, [%{type: :user, content: prompt}])

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "SDK error: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("sdk_clear", _params, socket) do
    {:noreply,
     socket
     |> assign(:sdk_messages, [])
     |> assign(:sdk_ref, nil)
     |> assign(:sdk_session_id, nil)}
  end

  # SDK message handlers - only show :result, skip streaming text deltas to avoid duplicates
  @impl true
  def handle_info({:claude_message, ref, %Message{type: :result} = message}, socket) do
    if socket.assigns.sdk_ref == ref do
      messages = socket.assigns.sdk_messages ++ [%{type: :assistant, message: message}]
      {:noreply, assign(socket, :sdk_messages, messages)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:claude_message, ref, %Message{}}, socket) do
    if socket.assigns.sdk_ref == ref do
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:claude_complete, ref, session_id}, socket) do
    if socket.assigns.sdk_ref == ref do
      socket =
        socket
        |> assign(:sdk_ref, nil)
        |> assign(:sdk_session_id, session_id)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:claude_error, ref, reason}, socket) do
    if socket.assigns.sdk_ref == ref do
      messages =
        socket.assigns.sdk_messages ++
          [%{type: :error, content: "Error: #{inspect(reason)}"}]

      socket =
        socket
        |> assign(:sdk_ref, nil)
        |> assign(:sdk_messages, messages)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Agents")
  end

  defp schedule_refresh(socket) do
    socket = cancel_timer(socket)
    ref = Process.send_after(self(), :refresh_agents, @default_refresh_ms)
    assign(socket, :timer_ref, ref)
  end

  defp cancel_timer(%{assigns: %{timer_ref: ref}} = socket) when is_reference(ref) do
    Process.cancel_timer(ref)
    assign(socket, :timer_ref, nil)
  end

  defp cancel_timer(socket), do: socket

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

  defp format_sdk_message(%Message{type: :result, content: text}), do: text
  defp format_sdk_message(%Message{type: :text, content: text}), do: text
  defp format_sdk_message(%Message{content: text}) when is_binary(text), do: text
  defp format_sdk_message(%Message{type: type}), do: "[#{type}]"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-100 px-4 sm:px-6 lg:px-8">
      <div class="max-w-3xl mx-auto">
        <%!-- Toolbar: refresh + actions --%>
        <div class="flex items-center justify-between py-5">
          <div class="flex items-center gap-3">
            <%!-- Agent count --%>
            <span class="text-[11px] font-mono tabular-nums text-base-content/30 tracking-wider uppercase">
              {length(@agents)} agents
            </span>
          </div>
          <div class="flex items-center gap-2">
            <button
              phx-click="toggle_new_session_drawer"
              class="btn btn-sm btn-primary gap-1.5 min-h-0 h-7 text-xs"
            >
              <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Agent
            </button>
            <button
              phx-click="toggle_sdk_demo"
              class="btn btn-sm btn-ghost gap-1.5 min-h-0 h-7 text-xs text-base-content/50 hover:text-base-content"
            >
              <.icon name="hero-command-line-mini" class="w-3.5 h-3.5" /> SDK
            </button>
            <label class="swap swap-rotate btn btn-ghost btn-xs btn-circle">
              <input type="checkbox" class="theme-controller" value="dark" />
              <.icon name="hero-sun" class="swap-on w-4 h-4" />
              <.icon name="hero-moon" class="swap-off w-4 h-4" />
            </label>
          </div>
        </div>

        <%!-- Search and Filters --%>
        <div class="sticky top-0 md:top-16 z-10 bg-base-100/85 backdrop-blur-md -mx-4 sm:-mx-6 lg:-mx-8 px-4 sm:px-6 lg:px-8 py-3 border-b border-base-content/5">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-3">
            <form phx-submit="search" phx-change="search" class="flex-1 max-w-sm">
              <label for="search" class="sr-only">Search agents</label>
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
              <button
                phx-click="filter_session"
                phx-value-filter="all"
                class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                  if(@session_filter == "all",
                    do: "bg-base-100 text-base-content shadow-sm",
                    else: "text-base-content/40 hover:text-base-content/60"
                  )}
              >
                All
              </button>
              <button
                phx-click="filter_session"
                phx-value-filter="active"
                class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                  if(@session_filter == "active",
                    do: "bg-base-100 text-success shadow-sm",
                    else: "text-base-content/40 hover:text-base-content/60"
                  )}
              >
                Active
              </button>
              <button
                phx-click="filter_session"
                phx-value-filter="completed"
                class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                  if(@session_filter == "completed",
                    do: "bg-base-100 text-base-content shadow-sm",
                    else: "text-base-content/40 hover:text-base-content/60"
                  )}
              >
                Completed
              </button>
              <button
                phx-click="filter_session"
                phx-value-filter="archived"
                class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                  if(@session_filter == "archived",
                    do: "bg-base-100 text-warning shadow-sm",
                    else: "text-base-content/40 hover:text-base-content/60"
                  )}
              >
                Archived
              </button>
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

        <%!-- Agent list --%>
        <div class="mt-2 divide-y divide-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm px-4">
          <%= if @agents == [] do %>
            <.empty_state
              id="agents-empty"
              title="No agents found"
              subtitle="Try adjusting your search or filters"
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
                    <%= if agent.project_name do %>
                      <span class="text-base-content/15">/</span>
                      <span>{agent.project_name}</span>
                    <% end %>
                    <span class="text-base-content/15">/</span>
                    <span class="tabular-nums">{relative_time(agent.started_at)}</span>
                  </div>
                  <%= if agent.agent && agent.agent.description do %>
                    <p class="text-xs text-base-content/35 mt-1 truncate max-w-lg">
                      {agent.agent.description}
                    </p>
                  <% end %>
                </div>

                <%!-- Actions (visible on hover) --%>
                <div
                  class="flex items-center gap-0.5 flex-shrink-0"
                  phx-click="noop"
                >
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
      id="new-session-modal"
      show={@show_new_session_drawer}
      projects={@projects}
      current_project={nil}
      toggle_event="toggle_new_session_drawer"
      submit_event="create_new_session"
    />

    <%!-- SDK Demo Chat --%>
    <%= if @show_sdk_demo do %>
      <div class="fixed bottom-4 right-4 w-96 z-50 flex flex-col bg-base-100 border border-base-content/10 rounded-xl shadow-2xl max-h-[500px] overflow-hidden">
        <div class="flex items-center justify-between px-4 py-2.5 border-b border-base-content/5 bg-base-200/30">
          <div class="flex items-center gap-2">
            <.icon name="hero-command-line-mini" class="w-3.5 h-3.5 text-primary/60" />
            <span class="text-xs font-semibold text-base-content/70">SDK Chat</span>
          </div>
          <div class="flex items-center gap-1">
            <%= if @sdk_session_id do %>
              <span class="text-[10px] font-mono text-base-content/25 truncate max-w-[120px]">
                {@sdk_session_id}
              </span>
            <% end %>
            <button
              phx-click="sdk_clear"
              class="btn btn-ghost btn-xs btn-square text-base-content/30"
              title="Clear"
            >
              <.icon name="hero-trash-mini" class="w-3 h-3" />
            </button>
            <button
              phx-click="toggle_sdk_demo"
              class="btn btn-ghost btn-xs btn-square text-base-content/30"
              title="Close"
            >
              <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        <div
          id="sdk-messages"
          phx-hook="ScrollToBottom"
          class="flex-1 overflow-y-auto p-3 space-y-2.5 min-h-[200px] max-h-[360px]"
        >
          <%= if @sdk_messages == [] do %>
            <div class="text-center text-base-content/25 text-xs py-10">
              Send a message to test the SDK pipeline
            </div>
          <% else %>
            <%= for msg <- @sdk_messages do %>
              <%= case msg.type do %>
                <% :user -> %>
                  <div class="flex justify-end">
                    <div class="bg-primary/90 text-primary-content rounded-xl rounded-br-sm px-3 py-2 text-sm max-w-[80%]">
                      {msg.content}
                    </div>
                  </div>
                <% :assistant -> %>
                  <div class="flex justify-start">
                    <div class="bg-base-200/60 rounded-xl rounded-bl-sm px-3 py-2 text-sm max-w-[80%] whitespace-pre-wrap">
                      {format_sdk_message(msg.message)}
                    </div>
                  </div>
                <% :error -> %>
                  <div class="flex justify-start">
                    <div class="bg-error/10 text-error rounded-xl px-3 py-2 text-sm max-w-[80%]">
                      {msg.content}
                    </div>
                  </div>
                <% _ -> %>
              <% end %>
            <% end %>
          <% end %>
          <%= if @sdk_ref do %>
            <div class="flex justify-start">
              <span class="loading loading-dots loading-xs text-base-content/30"></span>
            </div>
          <% end %>
        </div>

        <form phx-submit="sdk_send_message" class="px-3 py-2.5 border-t border-base-content/5">
          <div class="flex gap-2">
            <input
              type="text"
              name="prompt"
              value={@sdk_prompt}
              placeholder="Type a message..."
              class="input input-sm flex-1 bg-base-200/50 border-base-content/8 text-sm placeholder:text-base-content/25"
              autocomplete="off"
              disabled={@sdk_ref != nil}
            />
            <button
              type="submit"
              class="btn btn-primary btn-sm btn-square"
              disabled={@sdk_ref != nil}
            >
              <.icon name="hero-paper-airplane-mini" class="w-3.5 h-3.5" />
            </button>
          </div>
        </form>
      </div>
    <% end %>
    """
  end
end
