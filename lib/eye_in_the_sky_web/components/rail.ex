defmodule EyeInTheSkyWeb.Components.Rail do
  @moduledoc false
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Events

  import EyeInTheSkyWeb.Components.Rail.Flyout
  import EyeInTheSkyWeb.Components.Rail.ProjectSwitcher, only: [project_switcher: 1]
  import EyeInTheSkyWeb.Components.Rail.Helpers, only: [project_initial: 1]
  import EyeInTheSkyWeb.Components.Rail.FilePanel, only: [file_panel: 1, rail_item: 1]

  # Modals previously embedded inside flyout.ex — now rendered at rail top level
  # so the flyout component stays focused on navigation concerns only.
  import EyeInTheSkyWeb.Components.Rail.Modals.RailModal, only: [rail_modal: 1]
  import EyeInTheSkyWeb.Components.Rail.Modals.TaskDetail, only: [task_detail_modal: 1]
  import EyeInTheSkyWeb.Components.Rail.Modals.NoteDetail, only: [note_detail_modal: 1]
  import EyeInTheSkyWeb.Components.Rail.Modals.NewChannel, only: [new_channel_modal: 1]

  alias EyeInTheSky.Claude.RateLimitClient
  alias EyeInTheSky.{Notifications, Projects}
  alias EyeInTheSkyWeb.Components.NewSessionModal

  alias EyeInTheSkyWeb.Components.Rail.{
    FileActions,
    FilterActions,
    Loader,
    ProjectActions,
    RailSessionActions,
    RailStateActions,
    SectionActions
  }

  @section_map %{
    sessions: :sessions,
    overview: :sessions,
    tasks: :tasks,
    kanban: :tasks,
    prompts: :prompts,
    chat: :chat,
    notes: :notes,
    skills: :skills,
    teams: :teams,
    canvas: :canvas,
    canvases: :canvas,
    notifications: :notifications,
    usage: :usage,
    config: :sessions,
    jobs: :jobs,
    settings: :sessions,
    agents: :agents,
    files: :files,
    bookmarks: :sessions
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        projects: [],
        flyout_open: true,
        proj_picker_open: false,
        active_section: nil,
        flyout_sessions: [],
        flyout_channels: [],
        unread_counts: %{},
        notification_count: 0,
        new_project_path: nil,
        renaming_project_id: nil,
        rename_value: "",
        mobile_open: false,
        sidebar_project: nil,
        sidebar_tab: :sessions,
        active_channel_id: nil,
        workspace: nil,
        scope_type: :project,
        flyout_canvases: [],
        flyout_teams: [],
        team_search: "",
        team_status: "active",
        flyout_tasks: [],
        task_search: "",
        task_state_filter: nil,
        session_sort: :last_activity,
        session_name_filter: "",
        session_show: :twenty,
        session_scope: :current,
        session_project_visible: %{},
        session_project_collapsed: MapSet.new(),
        rail_modal: nil,
        flyout_agents: [],
        agent_search: "",
        agent_scope: "all",
        flyout_notes: [],
        note_search: "",
        note_parent_type: nil,
        flyout_skills: [],
        skill_search: "",
        skill_scope: "all",
        flyout_prompts: [],
        prompt_search: "",
        prompt_scope: "all",
        flyout_jobs: [],
        flyout_file_nodes: [],
        flyout_file_expanded: MapSet.new(),
        flyout_file_children: %{},
        flyout_file_error: nil,
        flyout_usage: nil,
        file_tabs: [],
        active_tab_path: nil,
        show_new_session_form: false,
        show_new_channel_form: false,
        prefill_agent_slug: nil,
        prefill_agent_name: nil,
        disable_auth: Application.get_env(:eye_in_the_sky, :disable_auth, false)
      )

    # Skip DB queries on the dead render (mount runs twice — static + connected).
    # This LiveView mounts once and persists across navigation.
    if connected?(socket) do
      Events.subscribe_rail_context()
      Events.subscribe_rail_unread_counts()
      Events.subscribe_rail_session_update()
      Events.subscribe_rail_notifications_refresh()
      Events.subscribe_rail_projects_refresh()
      Events.subscribe_rail_channels_refresh()

      {:ok,
       assign(socket,
         projects: Projects.list_projects_for_sidebar(),
         flyout_sessions: Loader.load_flyout_sessions(nil),
         notification_count: Notifications.unread_count()
       ), layout: false}
    else
      {:ok, socket, layout: false}
    end
  end

  # Page LiveView navigation — adopt new sidebar context broadcast by page LiveViews.
  @impl true
  def handle_info({:rail_context, %{sidebar_tab: sidebar_tab, sidebar_project: sidebar_project, active_channel_id: active_channel_id}}, socket) do
    previous_tab = socket.assigns[:sidebar_tab]
    previous_project = socket.assigns[:sidebar_project]
    next_section = Map.get(@section_map, sidebar_tab, :sessions)

    socket =
      socket
      |> assign(:sidebar_tab, sidebar_tab)
      |> assign(:active_channel_id, active_channel_id)

    # Only adopt sidebar_project if non-nil — prevents pages without a project
    # from clearing a project locally selected via the rail's own project picker.
    socket =
      if not is_nil(sidebar_project) do
        assign(socket, :sidebar_project, sidebar_project)
      else
        socket
      end

    socket = maybe_reload_on_project_change(socket, previous_project, sidebar_project)
    socket = maybe_reload_on_tab_change(socket, previous_tab, sidebar_tab, next_section)

    {:noreply, socket}
  end

  # Chat unread counts pushed by chat_live / chat_live/pubsub_handlers
  def handle_info({:rail_unread_counts, counts}, socket) do
    {:noreply, assign(socket, :unread_counts, counts)}
  end

  # Session update pushed by nav_hook
  def handle_info({:rail_session_updated, session}, socket) do
    sessions = socket.assigns[:flyout_sessions] || []

    updated_sessions =
      if Enum.any?(sessions, &(&1.id == session.id)) do
        Enum.map(sessions, fn s -> if s.id == session.id, do: session, else: s end)
      else
        Loader.load_flyout_sessions(
          socket.assigns[:sidebar_project],
          socket.assigns[:session_sort] || :last_activity,
          socket.assigns[:session_name_filter] || "",
          socket.assigns[:session_show] || :twenty
        )
      end

    {:noreply, assign(socket, :flyout_sessions, updated_sessions)}
  end

  # Notification refresh from floating_chat_live
  def handle_info(:rail_refresh_notifications, socket) do
    {:noreply, assign(socket, :notification_count, Notifications.unread_count())}
  end

  # Project list refresh from floating_chat_live
  def handle_info(:rail_refresh_projects, socket) do
    {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
  end

  # Channel list refresh from floating_chat_live
  def handle_info(:rail_refresh_channels, socket) do
    {:noreply, assign(socket, :flyout_channels, Loader.load_flyout_channels(socket.assigns.sidebar_project))}
  end

  @impl true
  def handle_event("toggle_section", params, socket) do
    {:noreply, new_socket} = SectionActions.handle_toggle_section(params, socket)
    {:noreply, maybe_start_usage_async(new_socket, new_socket.assigns.active_section)}
  end

  def handle_event("close_flyout", _params, socket),
    do: SectionActions.handle_close_flyout(socket)

  def handle_event("toggle_collapsed", _params, socket),
    do: RailStateActions.handle_toggle_collapsed(socket)

  def handle_event("open_flyout", params, socket) do
    # Wrap like toggle_section: opening on the :usage section must kick off
    # the async usage fetch or the flyout spins forever (Codex bug hunt).
    {:noreply, new_socket} = SectionActions.handle_open_flyout(params, socket)
    {:noreply, maybe_start_usage_async(new_socket, new_socket.assigns.active_section)}
  end

  def handle_event("open_mobile_section", params, socket) do
    {:noreply, new_socket} = SectionActions.handle_open_mobile_section(params, socket)
    {:noreply, maybe_start_usage_async(new_socket, new_socket.assigns.active_section)}
  end

  def handle_event("refresh_usage", params, socket),
    do: RailStateActions.handle_refresh_usage(params, socket)

  def handle_event("restore_rail_state", params, socket),
    do: RailStateActions.handle_restore_rail_state(params, socket)

  def handle_event("toggle_proj_picker", params, socket),
    do: RailStateActions.handle_toggle_proj_picker(params, socket)

  def handle_event("close_proj_picker", params, socket),
    do: RailStateActions.handle_close_proj_picker(params, socket)

  def handle_event("open_mobile", params, socket),
    do: RailStateActions.handle_open_mobile(params, socket)

  def handle_event("select_project", params, socket),
    do: ProjectActions.handle_select_project_with_reload(params, socket)

  def handle_event("select_workspace", _params, socket),
    do: ProjectActions.handle_select_workspace(socket)

  def handle_event("show_new_project", _params, socket),
    do: ProjectActions.handle_show_new_project(socket)

  # Tauri JS bridge pushes this after the user picks a folder in the native dialog.
  def handle_event("folder_picked", params, socket),
    do: ProjectActions.handle_folder_picked(params, socket)

  # Tauri JS bridge: open a project in its own window.
  def handle_event("open_in_window", params, socket),
    do: ProjectActions.handle_open_in_window(params, socket)

  def handle_event("cancel_new_project", _params, socket),
    do: ProjectActions.handle_cancel_new_project(socket)

  def handle_event("update_project_path", params, socket),
    do: ProjectActions.handle_update_project_path(params, socket)

  def handle_event("create_project", params, socket),
    do: ProjectActions.handle_create_project(params, socket)

  def handle_event("new_session", params, socket),
    do: ProjectActions.handle_new_session(params, socket)

  def handle_event("start_rename_project", params, socket),
    do: ProjectActions.handle_start_rename(params, socket)

  def handle_event("cancel_rename_project", _params, socket),
    do: ProjectActions.handle_cancel_rename(socket)

  def handle_event("update_rename_value", params, socket),
    do: ProjectActions.handle_update_rename_value(params, socket)

  def handle_event("commit_rename_project", _params, socket),
    do: ProjectActions.handle_commit_rename(socket)

  def handle_event("delete_project", params, socket),
    do: ProjectActions.handle_delete_project(params, socket)

  # Rename via the context menu's own prompt dialog — a self-contained
  # request/response, unlike start_rename_project/commit_rename_project
  # (which target an inline-edit UI that no template currently renders).
  def handle_event("rename_project", params, socket),
    do: ProjectActions.handle_rename_project(params, socket)

  def handle_event("open_project_terminal", params, socket),
    do: ProjectActions.handle_open_terminal(params, socket)

  def handle_event("open_project_in_editor", params, socket),
    do: ProjectActions.handle_open_in_editor(params, socket)

  def handle_event("set_bookmark", params, socket),
    do: ProjectActions.handle_set_bookmark(params, socket)

  def handle_event("new_note", params, socket),
    do: RailStateActions.handle_new_note(params, socket)

  def handle_event("not_implemented", params, socket),
    do: RailStateActions.handle_not_implemented(params, socket)

  def handle_event("archive_session", params, socket),
    do: RailSessionActions.handle_archive_session(params, socket)

  def handle_event("rename_session", params, socket),
    do: RailSessionActions.handle_rename_session(params, socket)

  def handle_event("open_worktree", params, socket),
    do: RailSessionActions.handle_open_worktree(params, socket)

  def handle_event("toggle_new_session_drawer", params, socket),
    do: RailSessionActions.handle_toggle_new_session_drawer(params, socket)

  def handle_event("toggle_new_channel_form", params, socket),
    do: RailSessionActions.handle_toggle_new_channel_form(params, socket)

  def handle_event("open_new_session_with_agent", params, socket),
    do: RailSessionActions.handle_open_new_session_with_agent(params, socket)

  def handle_event("create_new_session", params, socket),
    do: RailSessionActions.handle_create_new_session(params, socket)

  def handle_event("create_channel", params, socket),
    do: RailSessionActions.handle_create_channel(params, socket)

  def handle_event("delete_channel", params, socket),
    do: RailSessionActions.handle_delete_channel(params, socket)

  def handle_event("rename_channel", params, socket),
    do: RailSessionActions.handle_rename_channel(params, socket)

  def handle_event("set_session_sort", params, socket),
    do: FilterActions.handle_set_session_sort(params, socket)

  def handle_event("update_session_name_filter", params, socket),
    do: FilterActions.handle_update_session_name_filter(params, socket)

  def handle_event("set_session_show", params, socket),
    do: FilterActions.handle_set_session_show(params, socket)

  def handle_event("set_session_scope", params, socket),
    do: FilterActions.handle_set_session_scope(params, socket)

  def handle_event("show_more_project_sessions", params, socket),
    do: RailStateActions.handle_show_more_project_sessions(params, socket)

  def handle_event("toggle_project_sessions", params, socket),
    do: RailStateActions.handle_toggle_project_sessions(params, socket)

  def handle_event("update_task_search", params, socket),
    do: FilterActions.handle_update_task_search(params, socket)

  def handle_event("set_task_state_filter", params, socket),
    do: FilterActions.handle_set_task_state_filter(params, socket)

  def handle_event("update_note_search", params, socket),
    do: FilterActions.handle_update_note_search(params, socket)

  def handle_event("set_note_parent_type", params, socket),
    do: FilterActions.handle_set_note_parent_type(params, socket)

  def handle_event("update_agent_search", params, socket),
    do: FilterActions.handle_update_agent_search(params, socket)

  def handle_event("set_agent_scope", params, socket),
    do: FilterActions.handle_set_agent_scope(params, socket)

  def handle_event("update_skill_search", params, socket),
    do: FilterActions.handle_update_skill_search(params, socket)

  def handle_event("set_skill_scope", params, socket),
    do: FilterActions.handle_set_skill_scope(params, socket)

  def handle_event("update_team_search", params, socket),
    do: FilterActions.handle_update_team_search(params, socket)

  def handle_event("set_team_status", params, socket),
    do: FilterActions.handle_set_team_status(params, socket)

  def handle_event("update_prompt_search", params, socket),
    do: FilterActions.handle_update_prompt_search(params, socket)

  def handle_event("set_prompt_scope", params, socket),
    do: FilterActions.handle_set_prompt_scope(params, socket)

  def handle_event("open_rail_modal", params, socket),
    do: RailStateActions.handle_open_rail_modal(params, socket)

  def handle_event("open_task_detail", params, socket),
    do: RailStateActions.handle_open_task_detail(params, socket)

  def handle_event("task_detail_nav", params, socket),
    do: RailStateActions.handle_task_detail_nav(params, socket)

  def handle_event("open_note_detail", params, socket),
    do: RailStateActions.handle_open_note_detail(params, socket)

  def handle_event("note_detail_nav", params, socket),
    do: RailStateActions.handle_note_detail_nav(params, socket)

  def handle_event("close_rail_modal", params, socket),
    do: RailStateActions.handle_close_rail_modal(params, socket)

  def handle_event("submit_rail_modal", params, socket),
    do: RailStateActions.handle_submit_rail_modal(params, socket)

  def handle_event("file_open", params, socket),
    do: FileActions.handle_file_open(params, socket)

  def handle_event("file_switch_tab", params, socket),
    do: FileActions.handle_file_switch_tab(params, socket)

  def handle_event("file_close_tab", params, socket),
    do: FileActions.handle_file_close_tab(params, socket)

  def handle_event("file_save", params, socket),
    do: FileActions.handle_file_save(params, socket)

  def handle_event("file_expand", params, socket),
    do: FileActions.handle_file_expand(params, socket)

  def handle_event("file_collapse", params, socket),
    do: FileActions.handle_file_collapse(params, socket)

  def handle_event("file_refresh", _params, socket),
    do: FileActions.handle_file_refresh(socket)

  def handle_event("reveal_file", params, socket),
    do: FileActions.handle_reveal_file(params, socket)

  def handle_event("open_file_in_editor", params, socket),
    do: FileActions.handle_open_file_in_editor(params, socket)

  def handle_event("rename_file", params, socket),
    do: FileActions.handle_rename_file(params, socket)

  @impl true
  def handle_async(:load_usage, {:ok, result}, socket) do
    {:noreply, assign(socket, :flyout_usage, result)}
  end

  def handle_async(:load_usage, {:exit, reason}, socket) do
    {:noreply, assign(socket, :flyout_usage, {:error, reason})}
  end

  defp maybe_reload_on_project_change(socket, same_project, same_project), do: socket

  defp maybe_reload_on_project_change(socket, _prev, new_project) do
    socket
    |> assign(
      :flyout_sessions,
      Loader.load_flyout_sessions(
        new_project,
        socket.assigns.session_sort,
        socket.assigns.session_name_filter,
        socket.assigns.session_show
      )
    )
    |> assign(:flyout_file_expanded, MapSet.new())
    |> assign(:flyout_file_children, %{})
    |> Loader.maybe_load_files(socket.assigns.active_section)
    |> Loader.maybe_load_agents(socket.assigns.active_section, new_project)
  end

  defp maybe_reload_on_tab_change(socket, same_tab, same_tab, _section), do: socket

  defp maybe_reload_on_tab_change(socket, _prev_tab, _next_tab, _next_section) do
    # Page navigation does not change the active flyout section.
    # The flyout only changes when the user explicitly swipes an icon in the strip.
    # Data for each section is lazy-loaded when toggle_section fires.
    assign(socket, :mobile_open, false)
  end

  defp maybe_start_usage_async(socket, :usage) do
    start_async(socket, :load_usage, fn -> RateLimitClient.fetch() end)
  end

  defp maybe_start_usage_async(socket, _section), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="rail-root"
      phx-hook="RailState"
      data-project-id={@sidebar_project && @sidebar_project.id}
      class="flex flex-row h-full min-w-0 relative group/rail"
    >
      <div
        :if={@mobile_open && @flyout_open}
        phx-click="close_flyout"
        class="md:hidden fixed inset-0 z-40 bg-black/40"
      />

      <%!-- Collapse chevron: pill attached to the rail's right edge, revealed on
           rail hover or keyboard focus. Same toggle as the vsbar button and the
           divider double-click (see #rail-divider + app.js). --%>
      <button
        id="rail-collapse-toggle"
        phx-click="toggle_collapsed"
        aria-expanded={to_string(@flyout_open)}
        aria-label={if @flyout_open, do: "Collapse sidebar", else: "Expand sidebar"}
        title={if @flyout_open, do: "Collapse sidebar", else: "Expand sidebar"}
        class={[
          "hidden md:grid place-items-center absolute -right-[13px] top-11 w-[26px] h-11 z-30",
          "rounded-full border border-base-content/15 bg-base-200 shadow-sm",
          "text-base-content/60 hover:text-base-content hover:border-primary/60",
          "opacity-0 group-hover/rail:opacity-100 focus-visible:opacity-100",
          "transition-opacity duration-150"
        ]}
      >
        <.icon
          name={if @flyout_open, do: "hero-chevron-left", else: "hero-chevron-right"}
          class="size-3.5"
        />
      </button>

      <%!-- Divider strip: invisible 6px double-click target on the rail's right
           edge (bonus gesture — the chevron is the discoverable affordance).
           dblclick wiring in app.js clicks #rail-collapse-toggle. --%>
      <div
        id="rail-divider"
        class="hidden md:block absolute right-0 inset-y-0 w-[6px] z-20 select-none"
        aria-hidden="true"
      />

      <nav
        id="rail-icon-strip"
        class="w-[52px] flex-shrink-0 flex flex-col items-center py-2 gap-1 border-r border-base-content/8 bg-base-100 z-20"
      >
        <button
          phx-click="toggle_proj_picker"
          class={[
            "w-8 h-8 rounded-lg mb-2 flex items-center justify-center text-sm font-bold text-white transition-all",
            "bg-primary hover:opacity-90",
            if(@proj_picker_open, do: "ring-2 ring-primary ring-offset-2 ring-offset-base-100")
          ]}
          title="Switch project"
          aria-label="Switch project"
        >
          {project_initial(@sidebar_project)}
        </button>

        <div class="mb-3" />
        <.rail_item
          section={:files}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-folder"
          label="Files"        />
        <.rail_item
          section={:sessions}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="lucide-bot-message-square"
          label="Sessions"        />
        <.rail_item
          section={:tasks}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="lucide-kanban"
          label="Tasks"        />
        <.rail_item
          section={:notes}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-pencil-square"
          label="Notes"        />
        <.rail_item
          section={:agents}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="lucide-robot"
          label="Agents"        />
        <.rail_item
          section={:skills}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-bolt"
          label="Skills"        />
        <.rail_item
          section={:prompts}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-document-text"
          label="Prompts"        />
        <.rail_item
          section={:teams}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-users"
          label="Teams"        />
        <.rail_item
          section={:jobs}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-clock"
          label="Jobs"        />
        <.rail_item
          section={:canvas}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-squares-2x2"
          label="Canvas"        />
        <.rail_item
          section={:chat}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-chat-bubble-left-ellipsis"
          label="Chat"        />
        <.rail_item
          section={:usage}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-chart-bar"
          label="Usage"        />

        <div class="flex-1" />
        <div class="mb-3" />

        <div class="tooltip tooltip-right" data-tip="Notifications">
          <.link
            navigate="/notifications"
            class={[
              "relative w-8 h-8 flex items-center justify-center rounded-lg transition-colors",
              "text-base-content/45 hover:bg-base-content/[0.06] hover:rounded-lg"
            ]}
            aria-label="Notifications"
          >
            <.icon name="hero-bell-mini" class="size-4" />
            <span
              :if={@notification_count > 0}
              class="absolute -top-0.5 -right-0.5 min-w-[14px] h-[14px] bg-error text-white text-nano font-bold rounded-full flex items-center justify-center px-0.5"
            >
              {@notification_count}
            </span>
          </.link>
        </div>

        <div class="tooltip tooltip-right" data-tip="IAM Policies">
          <.link
            navigate="/iam/policies"
            class="w-8 h-8 flex items-center justify-center rounded-lg text-base-content/45 hover:bg-base-content/[0.06] hover:rounded-lg transition-colors"
            aria-label="IAM Policies"
          >
            <.icon name="hero-shield-check-mini" class="size-4" />
          </.link>
        </div>

        <div class="tooltip tooltip-right" data-tip="Claude Config">
          <.link
            navigate="/config"
            class="w-8 h-8 flex items-center justify-center rounded-lg text-base-content/45 hover:bg-base-content/[0.06] hover:rounded-lg transition-colors"
            aria-label="Claude Config"
          >
            <.custom_icon name="lucide-file-cog" class="size-4" />
          </.link>
        </div>

        <div class="tooltip tooltip-right" data-tip="Settings">
          <.link
            navigate="/settings"
            class="w-8 h-8 flex items-center justify-center rounded-lg text-base-content/45 hover:bg-base-content/[0.06] hover:rounded-lg transition-colors"
            aria-label="Settings"
          >
            <.icon name="hero-cog-6-tooth-mini" class="size-4" />
          </.link>
        </div>

        <div :if={!@disable_auth} class="tooltip tooltip-right" data-tip="Sign out">
          <.link
            href="/auth/logout"
            method="delete"
            class="w-8 h-8 flex items-center justify-center rounded-lg text-base-content/45 hover:bg-base-content/[0.06] hover:rounded-lg transition-colors"
            aria-label="Sign out"
          >
            <.icon name="hero-arrow-left-on-rectangle-mini" class="size-4" />
          </.link>
        </div>
      </nav>

      <.project_switcher
        :if={@proj_picker_open}
        projects={@projects}
        sidebar_project={@sidebar_project}
        open={@proj_picker_open}
        new_project_path={@new_project_path}
        workspace={@workspace}
        scope_type={@scope_type}
      />

      <.flyout
        open={@flyout_open}
        mobile_open={@mobile_open}
        active_section={@active_section}
        sidebar_project={@sidebar_project}
        active_channel_id={@active_channel_id}
        flyout_sessions={@flyout_sessions}
        flyout_channels={@flyout_channels}
        unread_counts={@unread_counts}
        flyout_canvases={@flyout_canvases}
        flyout_teams={@flyout_teams}
        team_search={@team_search}
        team_status={@team_status}
        flyout_tasks={@flyout_tasks}
        task_search={@task_search}
        task_state_filter={@task_state_filter}
        session_sort={@session_sort}
        session_name_filter={@session_name_filter}
        session_show={@session_show}
        session_scope={@session_scope}
        session_project_visible={@session_project_visible}
        session_project_collapsed={@session_project_collapsed}
        projects={@projects}
        notification_count={@notification_count}
        flyout_agents={@flyout_agents}
        agent_search={@agent_search}
        agent_scope={@agent_scope}
        flyout_notes={@flyout_notes}
        note_search={@note_search}
        note_parent_type={@note_parent_type}
        flyout_skills={@flyout_skills}
        skill_search={@skill_search}
        skill_scope={@skill_scope}
        flyout_prompts={@flyout_prompts}
        prompt_search={@prompt_search}
        prompt_scope={@prompt_scope}
        flyout_jobs={@flyout_jobs}
        flyout_file_nodes={@flyout_file_nodes}
        flyout_file_expanded={@flyout_file_expanded}
        flyout_file_children={@flyout_file_children}
        flyout_file_error={@flyout_file_error}
        flyout_usage={@flyout_usage}
      />

      <%!-- ── Channel modal ── --%>
      <.new_channel_modal
        :if={@show_new_channel_form}
      />

      <%!-- ── Rail modal (new task / new prompt) ── --%>
      <.rail_modal
        :if={@rail_modal in [:new_task, :new_prompt]}
        modal={@rail_modal}
      />

      <%!-- ── Task detail modal ── --%>
      <.task_detail_modal
        :if={match?({:view_task, _, _}, @rail_modal)}
        task={Enum.at(elem(@rail_modal, 2), elem(@rail_modal, 1))}
        index={elem(@rail_modal, 1)}
        total={length(elem(@rail_modal, 2))}
      />

      <%!-- ── Note detail modal ── --%>
      <.note_detail_modal
        :if={match?({:view_note, _, _}, @rail_modal)}
        note={Enum.at(elem(@rail_modal, 2), elem(@rail_modal, 1))}
        index={elem(@rail_modal, 1)}
        total={length(elem(@rail_modal, 2))}
      />

      <.file_panel
        file_tabs={@file_tabs}
        active_tab_path={@active_tab_path}
        socket={@socket}
      />
      <%!-- Splitter handle for split-view mode. Visibility driven by data-editor-mode on <html>. --%>
      <%!-- role=separator makes this a keyboard-focusable resize handle per ARIA spec.
           aria-valuenow/min/max are kept in sync by the EditorLayout hook. --%>
      <div
        id="editor-splitter"
        role="separator"
        aria-label="Resize editor panel"
        aria-orientation="vertical"
        aria-valuenow="0"
        aria-valuemin="320"
        aria-valuemax="9999"
        tabindex="0"
      >
      </div>

      <.live_component
        module={NewSessionModal}
        id="rail-new-session-modal"
        show={@show_new_session_form}
        projects={@projects}
        current_project={@sidebar_project}
        toggle_event="toggle_new_session_drawer"
        submit_event="create_new_session"
        target={nil}
        prefill_agent_slug={@prefill_agent_slug}
        prefill_agent_name={@prefill_agent_name}
      />
    </div>
    """
  end
end
