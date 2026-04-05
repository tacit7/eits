defmodule EyeInTheSkyWeb.AgentLive.Index do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Sessions
  alias EyeInTheSkyWeb.Canvases
  alias EyeInTheSkyWeb.AgentLive.CanvasHandlers
  alias EyeInTheSkyWeb.Helpers.AgentCreationHelpers
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers
  import EyeInTheSkyWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWeb.Components.SessionCard
  import EyeInTheSkyWeb.Components.AgentList
  import EyeInTheSkyWeb.Helpers.SessionFilters
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  require Logger

  @default_refresh_ms 300_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      subscribe_agents()
      subscribe_agent_working()
    end

    projects = EyeInTheSky.Projects.list_projects()

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
      |> assign(:sidebar_tab, :sessions)
      |> assign(:sidebar_project, nil)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:show_delete_confirm, false)
      |> assign(:editing_session_id, nil)
      |> assign(:canvases, Canvases.list_canvases())
      |> assign(:show_new_canvas_for, nil)
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
    with {:session, {:ok, session}} <- {:session, Sessions.get_session(target_session_id)},
         {:channel, {:ok, global_channel}} <- {:channel, EyeInTheSky.Channels.find_global_channel(session)},
         {:send, {:ok, _message}} <-
           {:send,
            EyeInTheSky.ChannelMessages.send_channel_message(%{
              channel_id: global_channel.id,
              session_id: "web-user",
              sender_role: "user",
              recipient_role: "agent",
              provider: "claude",
              body: body
            })} do
      maybe_continue_session(session, body, socket)
    else
      {:session, _} -> {:noreply, put_flash(socket, :error, "Session not found")}
      {:channel, _} -> {:noreply, put_flash(socket, :error, "Global channel not found")}
      {:send, _} -> {:noreply, put_flash(socket, :error, "Failed to send message")}
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
  def handle_event(action, %{"session_id" => session_id}, socket)
      when action in ["archive_session", "unarchive_session", "delete_session"] do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- apply_session_action(action, session) do
      {:noreply, socket |> load_agents() |> put_flash(:info, "Session #{action_label(action)}")}
    else
      {:error, reason} ->
        Logger.error("#{action} failed for #{session_id}: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to #{action_label(action)}")}
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
  def handle_event("confirm_delete_selected", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, true)}
  end

  @impl true
  def handle_event("cancel_delete_selected", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, false)}
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
      |> assign(:show_delete_confirm, false)
      |> load_agents()
      |> put_flash(:info, "Deleted #{deleted} session#{if deleted != 1, do: "s"}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("navigate_dm", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dm/#{id}")}
  end

  @impl true
  def handle_event("rename_session", %{"session_id" => session_id}, socket) do
    case parse_int(session_id) do
      nil -> {:noreply, socket}
      id -> {:noreply, assign(socket, :editing_session_id, id)}
    end
  end

  @impl true
  def handle_event("save_session_name", %{"session_id" => session_id, "name" => name}, socket) do
    name = String.trim(name)

    if name != "", do: rename_session(session_id, name)

    {:noreply, socket |> assign(:editing_session_id, nil) |> load_agents()}
  end

  @impl true
  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, :editing_session_id, nil)}
  end

  @impl true
  def handle_event("toggle_new_session_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_session_drawer, !socket.assigns.show_new_session_drawer)}
  end

  @impl true
  def handle_event("create_new_session", params, socket) do
    project_id = parse_int(params["project_id"])

    if is_nil(project_id) do
      {:noreply, put_flash(socket, :error, "Invalid project")}
    else
      create_new_session_with_project(params, project_id, socket)
    end
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("show_new_canvas_form", params, socket),
    do: CanvasHandlers.handle_event("show_new_canvas_form", params, socket)

  @impl true
  def handle_event("add_to_canvas", params, socket),
    do: CanvasHandlers.handle_event("add_to_canvas", params, socket)

  @impl true
  def handle_event("add_to_new_canvas", params, socket),
    do: CanvasHandlers.handle_event("add_to_new_canvas", params, socket)

  defp create_new_session_with_project(params, project_id, socket) do
    case EyeInTheSky.Projects.get_project(project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Project not found")}

      project ->
        do_create_session(params, project, socket)
    end
  end

  defp do_create_session(params, project, socket) do
    description = params["description"]
    agent_name = params["agent_name"] || String.slice(description || "", 0, 60)

    opts =
      AgentCreationHelpers.build_opts(params,
        project_path: project.path,
        description: agent_name,
        instructions: description
      )

    # Override project_id with the resolved struct id (params may have a string id
    # that differs from the resolved project; ensure consistency)
    opts =
      opts
      |> Keyword.put(:project_id, project.id)
      |> Keyword.put(:name, if(agent_name != "", do: agent_name))

    Logger.info(
      "create_new_session: model=#{opts[:model]}, effort=#{inspect(opts[:effort_level])}, project_id=#{project.id}, project_path=#{project.path}"
    )

    case AgentManager.create_agent(opts) do
      {:ok, result} ->
        Logger.info(
          "create_new_session: agent created - agent_id=#{result.agent.id}, session_id=#{result.agent.id}, session_uuid=#{result.agent.uuid}"
        )

        {:noreply,
         socket
         |> assign(:show_new_session_drawer, false)
         |> push_navigate(to: ~p"/dm/#{result.session.id}")}

      {:error, reason} ->
        Logger.error("create_new_session: failed - #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info(:refresh_agents, socket) do
    socket = socket |> load_agents() |> schedule_refresh()
    {:noreply, socket}
  end

  @impl true
  def handle_info({event, _agent}, socket)
      when event in [:agent_created, :agent_updated, :agent_deleted] do
    {:noreply, load_agents(socket)}
  end

  @impl true
  def handle_info({:agent_working, msg}, socket) do
    AgentStatusHelpers.handle_agent_working(socket, msg, fn socket, session_id ->
      update_agent_status_in_list(socket, session_id, "working")
    end)
  end

  @impl true
  def handle_info({:agent_stopped, msg}, socket) do
    AgentStatusHelpers.handle_agent_stopped(socket, msg, fn socket, session_id ->
      # For agent_stopped, we need to handle the status field from the message if present
      status = extract_stopped_status(msg)
      update_agent_status_in_list(socket, session_id, status)
    end)
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp extract_stopped_status(%{status: status}) when is_binary(status) and status != "", do: status
  defp extract_stopped_status(%{status: _}), do: "completed"
  defp extract_stopped_status(_), do: "idle"

  defp apply_action(socket, :index, %{"new" => "1"}) do
    socket
    |> assign(:page_title, "Agents")
    |> assign(:show_new_session_drawer, true)
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
    now = DateTime.utc_now()

    updated_agents =
      socket.assigns.agents
      |> Enum.map(&apply_agent_status(&1, session_id, new_status, now))
      |> sort_agents(socket.assigns.sort_by)

    assign(socket, :agents, updated_agents)
  end

  defp apply_agent_status(agent, session_id, new_status, now) do
    if agent.id == session_id do
      agent = %{agent | status: new_status}
      if new_status == "idle", do: %{agent | last_activity_at: now}, else: agent
    else
      agent
    end
  end

  defp maybe_continue_session(session, body, socket) do
    case Agents.get_agent(session.agent_id) do
      {:ok, chat_agent} ->
        project_path =
          chat_agent.git_worktree_path ||
            (chat_agent.project && chat_agent.project.path)

        continue_with_project_path(session, body, project_path, chat_agent, socket)

      _ ->
        Logger.warning(
          "send_direct_message: agent #{session.agent_id} not found, message sent but session not continued"
        )

        {:noreply, socket}
    end
  end

  defp continue_with_project_path(_session, _body, nil, chat_agent, socket) do
    Logger.warning(
      "send_direct_message: agent #{chat_agent.id} has no path (git_worktree_path and project.path both nil), session not continued"
    )

    {:noreply, socket}
  end

  defp continue_with_project_path(session, body, project_path, _chat_agent, socket) do
    AgentManager.continue_session(
      session.id,
      direct_message_prompt(body),
      model: "sonnet",
      project_path: project_path
    )

    {:noreply, socket}
  end

  defp rename_session(session_id, name) do
    case Sessions.get_session(session_id) do
      {:ok, session} ->
        case Sessions.update_session(session, %{name: name}) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.warning("save_session_name: failed to rename session #{session_id}: #{inspect(reason)}")
        end

      _ ->
        :ok
    end
  end

  defp apply_session_action("archive_session", session), do: Sessions.archive_session(session)
  defp apply_session_action("unarchive_session", session), do: Sessions.unarchive_session(session)
  defp apply_session_action("delete_session", session), do: Sessions.delete_session(session)

  defp action_label("archive_session"), do: "archived"
  defp action_label("unarchive_session"), do: "unarchived"
  defp action_label("delete_session"), do: "deleted"

  defp direct_message_prompt(body) do
    """
    REMINDER: Use i-chat-send MCP tool to send your response to the channel.

    User message: #{body}
    """
  end

  # -- Render ---------------------------------------------------------------

  # This LiveView is large by necessity: it owns the full agents list page with
  # filtering, search, bulk selection, per-row context menus, canvas management,
  # inline rename, and a new-agent drawer. The render function is broken into
  # defp components (search_bar, bulk_action_bar, agent_row_menu,
  # delete_confirm_modal) to keep each section navigable.

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-100 min-h-full px-4 sm:px-6 lg:px-8">
      <div class="max-w-3xl mx-auto">
        <div class="flex items-center justify-between py-5">
          <span class="text-[11px] font-mono tabular-nums text-base-content/30 tracking-wider uppercase">
            {length(@agents)} agents
          </span>
          <div class="flex items-center gap-2">
            <button
              phx-click="toggle_new_session_drawer"
              class="btn btn-sm btn-primary gap-1.5 min-h-0 h-7 text-xs"
            >
              <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Agent
            </button>
            <label class="swap swap-rotate btn btn-ghost btn-xs btn-circle">
              <input type="checkbox" class="theme-controller" value="dark" />
              <.icon name="hero-sun" class="swap-on w-4 h-4" />
              <.icon name="hero-moon" class="swap-off w-4 h-4" />
            </label>
          </div>
        </div>

        <.search_bar search_query={@search_query} session_filter={@session_filter} />
        <.bulk_action_bar session_filter={@session_filter} agents={@agents} selected_ids={@selected_ids} />

        <div class="mt-2 divide-y divide-base-content/5 bg-base-100 rounded-xl shadow-sm px-4">
          <%= if @agents == [] do %>
            <.empty_state
              id="agents-empty"
              title="No agents found"
              subtitle="Try adjusting your search or filters"
            />
          <% else %>
            <div :for={agent <- @agents}>
              <.session_row
                session={agent}
                select_mode={@session_filter == "archived"}
                selected={MapSet.member?(@selected_ids, to_string(agent.id))}
                project_name={agent.project_name}
                editing_session_id={@editing_session_id}
              >
                <:actions>
                  <.agent_row_menu agent={agent} canvases={@canvases} show_new_canvas_for={@show_new_canvas_for} />
                </:actions>
              </.session_row>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <.delete_confirm_modal show_delete_confirm={@show_delete_confirm} selected_ids={@selected_ids} />

    <.live_component
      module={EyeInTheSkyWeb.Components.NewSessionModal}
      id="new-session-modal"
      show={@show_new_session_drawer}
      projects={@projects}
      current_project={nil}
      toggle_event="toggle_new_session_drawer"
      submit_event="create_new_session"
    />
    """
  end
end
