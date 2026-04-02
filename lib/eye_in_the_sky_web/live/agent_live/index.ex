defmodule EyeInTheSkyWeb.AgentLive.Index do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Sessions
  alias EyeInTheSkyWeb.Canvases
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers
  import EyeInTheSkyWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWeb.Components.Icons
  import EyeInTheSkyWeb.Components.SessionCard
  import EyeInTheSkyWeb.Helpers.SessionFilters
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [parse_budget: 1]

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
         {:channel, {:ok, global_channel}} <- {:channel, find_global_channel(session)},
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
      case Agents.get_agent(session.agent_id) do
        {:ok, chat_agent} ->
          project_path =
            chat_agent.git_worktree_path ||
              (chat_agent.project && chat_agent.project.path)

          if project_path do
            prompt_with_reminder = """
            REMINDER: Use i-chat-send MCP tool to send your response to the channel.

            User message: #{body}
            """

            EyeInTheSky.Agents.AgentManager.continue_session(
              session.id,
              prompt_with_reminder,
              model: "sonnet",
              project_path: project_path
            )

            {:noreply, socket}
          else
            Logger.warning(
              "send_direct_message: agent #{chat_agent.id} has no path (git_worktree_path and project.path both nil), session not continued"
            )

            {:noreply, socket}
          end

        _ ->
          Logger.warning(
            "send_direct_message: agent #{session.agent_id} not found, message sent but session not continued"
          )

          {:noreply, socket}
      end
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
    case Integer.parse(session_id) do
      {id, ""} -> {:noreply, assign(socket, :editing_session_id, id)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_session_name", %{"session_id" => session_id, "name" => name}, socket) do
    name = String.trim(name)

    if name != "" do
      case Sessions.get_session(session_id) do
        {:ok, session} ->
          case Sessions.update_session(session, %{name: name}) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Logger.warning("save_session_name: failed to rename session #{session_id}: #{inspect(reason)}")
          end

        _ ->
          :ok
      end
    end

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
    project_id =
      case Integer.parse(params["project_id"] || "") do
        {id, ""} -> id
        _ -> nil
      end

    if is_nil(project_id) do
      {:noreply, put_flash(socket, :error, "Invalid project")}
    else
      create_new_session_with_project(params, project_id, socket)
    end
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("add_to_canvas", %{"canvas-id" => cid, "session-id" => sid}, socket) do
    with {canvas_id, _} <- Integer.parse(cid),
         {session_id, _} <- Integer.parse(sid),
         %{} = canvas <- Canvases.get_canvas(canvas_id) do
      Canvases.add_session(canvas_id, session_id)

      send_update(EyeInTheSkyWeb.Components.CanvasOverlayComponent,
        id: "canvas-overlay",
        action: :open_canvas,
        canvas_id: canvas_id
      )

      {:noreply, put_flash(socket, :info, "Added to #{canvas.name}")}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_to_new_canvas", %{"session_id" => sid, "canvas_name" => name}, socket) do
    case Integer.parse(sid) do
      {session_id, _} ->
        canvas_name =
          if name && String.trim(name) != "",
            do: String.trim(name),
            else: "Canvas #{:os.system_time(:second)}"

        case Canvases.create_canvas(%{name: canvas_name}) do
          {:ok, canvas} ->
            Canvases.add_session(canvas.id, session_id)

            send_update(EyeInTheSkyWeb.Components.CanvasOverlayComponent,
              id: "canvas-overlay",
              action: :open_canvas,
              canvas_id: canvas.id
            )

            {:noreply, put_flash(socket, :info, "Added to #{canvas.name}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create canvas")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp create_new_session_with_project(params, project_id, socket) do
    case EyeInTheSky.Projects.get_project(project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Project not found")}

      project ->
        do_create_session(params, project, socket)
    end
  end

  defp do_create_session(params, project, socket) do
    agent_type = params["agent_type"] || "claude"
    model = params["model"]
    effort_level = params["effort_level"]
    max_budget_usd = parse_budget(params["max_budget_usd"])
    description = params["description"]
    agent_name = params["agent_name"] || String.slice(description || "", 0, 60)

    worktree =
      case params["worktree"] do
        nil -> nil
        "" -> nil
        v -> String.trim(v)
      end

    eits_workflow = params["eits_workflow"] || "1"

    opts = [
      agent_type: agent_type,
      model: model,
      effort_level: effort_level,
      max_budget_usd: max_budget_usd,
      project_id: project.id,
      project_path: project.path,
      description: agent_name,
      instructions: description,
      worktree: worktree,
      agent: params["agent"],
      eits_workflow: eits_workflow
    ]

    Logger.info(
      "create_new_session: model=#{model}, effort=#{inspect(effort_level)}, project_id=#{project.id}, project_path=#{project.path}"
    )

    case EyeInTheSky.Agents.AgentManager.create_agent(opts) do
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

  defp apply_session_action("archive_session", session), do: Sessions.archive_session(session)
  defp apply_session_action("unarchive_session", session), do: Sessions.unarchive_session(session)
  defp apply_session_action("delete_session", session), do: Sessions.delete_session(session)

  defp action_label("archive_session"), do: "archived"
  defp action_label("unarchive_session"), do: "unarchived"
  defp action_label("delete_session"), do: "deleted"

  # -- Function Components --------------------------------------------------

  @filter_tabs [
    {"all", "All", "text-base-content"},
    {"active", "Active", "text-success"},
    {"completed", "Completed", "text-base-content"},
    {"archived", "Archived", "text-warning"}
  ]

  defp filter_tabs(assigns) do
    assigns = assign(assigns, :tabs, @filter_tabs)

    ~H"""
    <div class="flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
      <button
        :for={{value, label, active_color} <- @tabs}
        phx-click="filter_session"
        phx-value-filter={value}
        class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
          if(@current == value,
            do: "bg-base-100 #{active_color} shadow-sm",
            else: "text-base-content/40 hover:text-base-content/60"
          )}
      >
        {label}
      </button>
    </div>
    """
  end

  # Sticky search input + filter tabs bar
  defp search_bar(assigns) do
    ~H"""
    <div class="sticky safe-top-sticky md:top-16 z-10 bg-base-100/85 backdrop-blur-md -mx-4 sm:-mx-6 lg:-mx-8 px-4 sm:px-6 lg:px-8 py-3 border-b border-base-content/5">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-3">
        <form phx-change="search" class="flex-1 max-w-sm">
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
        <.filter_tabs current={@session_filter} />
      </div>
    </div>
    """
  end

  # Select-all + bulk delete bar shown only in archived mode
  defp bulk_action_bar(assigns) do
    ~H"""
    <div :if={@session_filter == "archived" && @agents != []} class="mt-2 flex items-center gap-3 px-2 py-1.5">
      <input
        type="checkbox"
        checked={MapSet.size(@selected_ids) == length(@agents)}
        phx-click="toggle_select_all"
        class="checkbox checkbox-xs checkbox-primary"
      />
      <%= if MapSet.size(@selected_ids) > 0 do %>
        <span class="text-[11px] text-base-content/50 font-medium">
          {MapSet.size(@selected_ids)} selected
        </span>
        <button
          phx-click="confirm_delete_selected"
          class="btn btn-ghost btn-xs text-error/70 hover:text-error hover:bg-error/10 gap-1"
        >
          <.icon name="hero-trash-mini" class="w-3.5 h-3.5" /> Delete
        </button>
      <% else %>
        <span class="text-[11px] text-base-content/30">{length(@agents)} archived</span>
      <% end %>
    </div>
    """
  end

  # Per-row context menu (ellipsis dropdown) with canvas, rename, archive/delete
  defp agent_row_menu(assigns) do
    ~H"""
    <details class="md:opacity-0 md:group-hover:opacity-100 relative dropdown dropdown-end transition-all">
      <summary
        class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/35 hover:text-base-content/70 hover:bg-base-content/5 transition-colors cursor-pointer list-none"
        aria-label="More options"
      >
        <.icon name="hero-ellipsis-horizontal-mini" class="w-4 h-4" />
      </summary>
      <div class="dropdown-content z-50 mt-1 w-48 rounded-xl bg-base-300 dark:bg-[hsl(220,13%,18%)] shadow-xl p-1.5 flex flex-col gap-0.5">
        <%= if @agent.id do %>
          <a
            href={~p"/dm/#{@agent.id}"}
            target="_blank"
            class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors"
          >
            <.icon name="hero-arrow-top-right-on-square-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
            Open in new tab
          </a>
        <% end %>
        <button
          type="button"
          phx-click="rename_session"
          phx-value-session_id={@agent.id}
          class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
        >
          <.icon name="hero-pencil-square-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
          Rename
        </button>
        <%!-- Canvas submenu --%>
        <details class="group/canvas">
          <summary class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors cursor-pointer list-none">
            <.icon name="hero-squares-2x2-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
            <span class="flex-1">Canvas</span>
            <.icon name="hero-chevron-right-mini" class="w-3 h-3 text-base-content/40" />
          </summary>
          <div class="mt-0.5 ml-3 flex flex-col gap-0.5">
            <%= for canvas <- @canvases do %>
              <button
                type="button"
                phx-click="add_to_canvas"
                phx-value-canvas-id={canvas.id}
                phx-value-session-id={@agent.id}
                class="w-full flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm text-base-content/80 hover:bg-base-content/10 transition-colors text-left"
              >
                {canvas.name}
              </button>
            <% end %>
            <div class="border-t border-base-content/10 my-0.5" />
            <div id={"new-canvas-label-#{@agent.id}"}>
              <button
                type="button"
                class="w-full flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm text-secondary hover:bg-base-content/10 transition-colors text-left"
                onclick={"document.getElementById('new-canvas-label-#{@agent.id}').style.display='none'; document.getElementById('new-canvas-form-#{@agent.id}').style.display='block';"}
              >+ New canvas</button>
            </div>
            <div id={"new-canvas-form-#{@agent.id}"} style="display:none">
              <form phx-submit="add_to_new_canvas" phx-click="noop" class="flex flex-col gap-1 p-1">
                <input type="hidden" name="session_id" value={@agent.id} />
                <input type="text" name="canvas_name" class="input input-xs w-full" placeholder="Canvas name..." autocomplete="off" />
                <button type="submit" class="btn btn-primary btn-xs w-full">Create &amp; Add</button>
              </form>
            </div>
          </div>
        </details>
        <%= if @agent.agent && @agent.agent.uuid && @agent.uuid do %>
          <button
            id={"bookmark-btn-#{@agent.uuid}"}
            type="button"
            phx-hook="BookmarkAgent"
            data-agent-id={@agent.agent.uuid}
            data-session-id={@agent.uuid}
            data-agent-name={@agent.name || @agent.agent.description || "Agent"}
            data-agent-status={@agent.status}
            class="bookmark-button w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
            aria-label="Bookmark agent"
          >
            <.heart class="bookmark-icon w-4 h-4 text-base-content/60 flex-shrink-0" />
            <span class="bookmark-label">Favorite</span>
          </button>
        <% end %>
        <%= if @agent.uuid do %>
          <div class="border-t border-base-content/10 my-0.5" />
          <%= if @agent.archived_at do %>
            <button
              type="button"
              phx-click="unarchive_session"
              phx-value-session_id={@agent.id}
              class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-info hover:bg-base-content/10 transition-colors text-left"
            >
              <.icon name="hero-arrow-up-tray-mini" class="w-4 h-4 flex-shrink-0" />
              Unarchive
            </button>
            <button
              type="button"
              phx-click="delete_session"
              phx-value-session_id={@agent.id}
              class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-error hover:bg-base-content/10 transition-colors text-left"
            >
              <.icon name="hero-trash-mini" class="w-4 h-4 flex-shrink-0" />
              Delete
            </button>
          <% else %>
            <button
              type="button"
              phx-click="archive_session"
              phx-value-session_id={@agent.id}
              class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-warning hover:bg-base-content/10 transition-colors text-left"
            >
              <.icon name="hero-archive-box-mini" class="w-4 h-4 flex-shrink-0" />
              Archive
            </button>
          <% end %>
        <% end %>
      </div>
    </details>
    """
  end

  # Confirmation dialog for bulk-delete of selected archived sessions
  defp delete_confirm_modal(assigns) do
    ~H"""
    <dialog
      id="delete-confirm-modal"
      class={"modal " <> if(@show_delete_confirm, do: "modal-open", else: "")}
    >
      <div class="modal-box max-w-sm">
        <h3 class="text-lg font-bold">Delete sessions</h3>
        <p class="py-4 text-sm text-base-content/70">
          Permanently delete {MapSet.size(@selected_ids)} selected session{if MapSet.size(@selected_ids) != 1, do: "s"}? This cannot be undone.
        </p>
        <div class="modal-action">
          <button phx-click="cancel_delete_selected" class="btn btn-sm btn-ghost">Cancel</button>
          <button phx-click="delete_selected" class="btn btn-sm btn-error">Delete</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel_delete_selected">close</button>
      </form>
    </dialog>
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
                  <.agent_row_menu agent={agent} canvases={@canvases} />
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

  defp find_global_channel(session) do
    channels =
      if session.project_id,
        do: EyeInTheSky.Channels.list_channels_for_project(session.project_id),
        else: EyeInTheSky.Channels.list_channels()

    case Enum.find(channels, fn c -> c.name == "#global" end) do
      nil -> {:error, :channel_not_found}
      channel -> {:ok, channel}
    end
  end
end
