defmodule EyeInTheSkyWeb.Components.Rail do
  @moduledoc false
  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.Components.Rail.Flyout
  import EyeInTheSkyWeb.Components.Rail.ProjectSwitcher, only: [project_switcher: 1]
  import EyeInTheSkyWeb.Components.Rail.Helpers, only: [project_initial: 1]
  import EyeInTheSkyWeb.Components.Rail.FilePanel, only: [file_panel: 1, rail_item: 1]

  alias EyeInTheSky.{Notifications, Projects, Tasks, Prompts}
  alias EyeInTheSkyWeb.Components.Rail.{
    FileActions,
    FilterActions,
    Loader,
    ProjectActions,
    SectionActions
  }
  alias EyeInTheSkyWeb.Components.NewSessionModal
  alias EyeInTheSkyWeb.AgentLive.IndexActions

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
  def mount(socket) do
    socket =
      assign(socket,
        projects: [],
        flyout_open: true,
        proj_picker_open: false,
        active_section: :sessions,
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
        file_tabs: [],
        active_tab_path: nil,
        show_new_session_form: false,
        prefill_agent_slug: nil,
        prefill_agent_name: nil
      )

    # Skip DB queries on the dead render (mount runs twice — static + connected).
    # This component mounts on every page, so the unguarded path doubles DB load.
    if connected?(socket) do
      {:ok,
       assign(socket,
         projects: Projects.list_projects_for_sidebar(),
         flyout_sessions: Loader.load_flyout_sessions(nil),
         notification_count: Notifications.unread_count()
       )}
    else
      {:ok, socket}
    end
  end

  # Both clauses below are triggered via send_update from floating_chat_live.ex,
  # which attaches them as handle_info hooks (attach_hook(:fab_info, :handle_info, ...)).
  # handle_info only fires on connected sockets, so no connected?(socket) guard is needed.
  @impl true
  def update(%{notification_count: :refresh}, socket) do
    {:ok, assign(socket, :notification_count, Notifications.unread_count())}
  end

  def update(%{unread_counts: counts}, socket) do
    {:ok, assign(socket, :unread_counts, counts)}
  end

  def update(%{refresh_projects: true}, socket) do
    {:ok, assign(socket, :projects, Projects.list_projects_for_sidebar())}
  end

  # Targeted update from NavHook when a session is created/updated/stopped.
  # Replaces the session in-place if it's already in the list (status change).
  # Falls back to a full reload if the session is new (not yet in the list).
  def update(%{session_updated: session}, socket) do
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

    {:ok, assign(socket, :flyout_sessions, updated_sessions)}
  end

  def update(assigns, socket) do
    # Only adopt parent's sidebar_project if it's non-nil — prevents parent re-renders from
    # clearing a project that was locally selected via the rail's own project picker.
    sidebar_project =
      case assigns do
        %{sidebar_project: p} when not is_nil(p) -> p
        _ -> socket.assigns[:sidebar_project]
      end

    sidebar_tab = Map.get(assigns, :sidebar_tab, socket.assigns[:sidebar_tab] || :sessions)
    active_channel_id = Map.get(assigns, :active_channel_id, socket.assigns[:active_channel_id])
    workspace = Map.get(assigns, :workspace, socket.assigns[:workspace])
    scope_type = Map.get(assigns, :scope_type, socket.assigns[:scope_type] || :project)

    previous_tab = socket.assigns[:sidebar_tab]
    next_section = Map.get(@section_map, sidebar_tab, :sessions)

    previous_project = socket.assigns[:sidebar_project]

    socket =
      socket
      |> assign(:sidebar_tab, sidebar_tab)
      |> assign(:sidebar_project, sidebar_project)
      |> assign(:active_channel_id, active_channel_id)
      |> assign(:workspace, workspace)
      |> assign(:scope_type, scope_type)

    # Only reload flyout sessions when the project actually changes — not on every
    # parent re-render. Every PubSub broadcast through the parent would otherwise
    # fire a Sessions.list_sessions_filtered query on each page.
    socket =
      if sidebar_project != previous_project do
        socket
        |> assign(
          :flyout_sessions,
          Loader.load_flyout_sessions(
            sidebar_project,
            socket.assigns.session_sort,
            socket.assigns.session_name_filter,
            socket.assigns.session_show
          )
        )
        |> assign(:flyout_file_expanded, MapSet.new())
        |> assign(:flyout_file_children, %{})
        |> Loader.maybe_load_files(socket.assigns.active_section)
        |> Loader.maybe_load_agents(socket.assigns.active_section, sidebar_project)
      else
        socket
      end

    # On navigation (tab change): update active section and close mobile flyout.
    # Keeping these together avoids a duplicate conditional and makes the
    # "tab changed → reset nav state" intent explicit.
    socket =
      if sidebar_tab != previous_tab do
        socket
        |> assign(:active_section, next_section)
        |> assign(:mobile_open, false)
        |> Loader.maybe_load_sessions(next_section, sidebar_project)
        |> Loader.maybe_load_channels(next_section, sidebar_project)
        |> Loader.maybe_load_canvases(next_section)
        |> Loader.maybe_load_teams(next_section, sidebar_project)
        |> Loader.maybe_load_tasks(next_section, sidebar_project)
        |> Loader.maybe_load_jobs(next_section)
        |> Loader.maybe_load_notes(next_section, sidebar_project)
        |> Loader.maybe_load_files(next_section)
        |> Loader.maybe_load_agents(next_section, sidebar_project)
        |> Loader.maybe_load_skills(next_section, sidebar_project)
        |> Loader.maybe_load_prompts(next_section, sidebar_project)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_section", params, socket),
    do: SectionActions.handle_toggle_section(params, socket)

  def handle_event("close_flyout", _params, socket),
    do: SectionActions.handle_close_flyout(socket)

  def handle_event("restore_section", %{"section" => section_str}, socket),
    do: {:noreply, assign(socket, :active_section, Loader.parse_section(section_str))}

  # Restore the last selected project from localStorage after a cross-LiveView navigation.
  # Only applies when the parent has not already provided a project (sidebar_project is nil).
  # Project-scoped pages set sidebar_project in update/2 before the hook fires, so we
  # skip the restore in that case to avoid overriding the route-derived context.
  def handle_event("restore_project", %{"project_id" => id_str}, socket)
      when is_nil(socket.assigns.sidebar_project),
    do: ProjectActions.handle_restore_project(id_str, socket)

  def handle_event("restore_project", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_proj_picker", _params, socket),
    do: {:noreply, assign(socket, :proj_picker_open, !socket.assigns.proj_picker_open)}

  def handle_event("close_proj_picker", _params, socket),
    do: {:noreply, assign(socket, :proj_picker_open, false)}

  def handle_event("open_mobile", _params, socket),
    do: {:noreply, assign(socket, mobile_open: true, flyout_open: true)}

  def handle_event("select_project", params, socket),
    do: ProjectActions.handle_select_project_with_reload(params, socket)

  def handle_event("select_workspace", _params, socket),
    do: ProjectActions.handle_select_workspace(socket)

  def handle_event("show_new_project", _params, socket),
    do: ProjectActions.handle_show_new_project(socket)

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

  def handle_event("set_bookmark", params, socket),
    do: ProjectActions.handle_set_bookmark(params, socket)

  def handle_event("new_note", _params, socket),
    do: {:noreply, push_navigate(socket, to: "/notes/new")}

  def handle_event("not_implemented", _params, socket),
    do: {:noreply, put_flash(socket, :info, "Not implemented yet")}

  def handle_event("toggle_new_session_drawer", _params, socket),
    do: {:noreply, assign(socket, :show_new_session_form, !socket.assigns.show_new_session_form)}

  def handle_event("open_new_session_with_agent", %{"slug" => slug, "name" => name}, socket) do
    {:noreply,
     socket
     |> assign(:show_new_session_form, true)
     |> assign(:prefill_agent_slug, slug)
     |> assign(:prefill_agent_name, name)}
  end

  def handle_event("create_new_session", params, socket) do
    socket =
      socket
      |> assign(:show_new_session_form, false)
      |> assign(:prefill_agent_slug, nil)
      |> assign(:prefill_agent_name, nil)

    case params["submit_action"] do
      "chat" -> IndexActions.handle_create_new_session(params, socket)
      _ -> IndexActions.handle_launch_new_session(params, socket)
    end
  end

  def handle_event("set_session_sort", params, socket),
    do: FilterActions.handle_set_session_sort(params, socket)

  def handle_event("update_session_name_filter", params, socket),
    do: FilterActions.handle_update_session_name_filter(params, socket)

  def handle_event("set_session_show", params, socket),
    do: FilterActions.handle_set_session_show(params, socket)

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

  def handle_event("open_rail_modal", %{"type" => type}, socket) do
    modal =
      case type do
        "new_task" -> :new_task
        "new_prompt" -> :new_prompt
        _ -> nil
      end

    {:noreply, assign(socket, :rail_modal, modal)}
  end

  def handle_event("close_rail_modal", _params, socket),
    do: {:noreply, assign(socket, :rail_modal, nil)}

  def handle_event("submit_rail_modal", params, socket) do
    title = String.trim(params["title"] || "")
    body = String.trim(params["body"] || "")
    modal_type = socket.assigns.rail_modal
    project_id = socket.assigns.sidebar_project && socket.assigns.sidebar_project.id

    if title == "" do
      {:noreply, put_flash(socket, :error, "Title is required")}
    else
      result =
        case modal_type do
          :new_task ->
            Tasks.create_task(%{title: title, body: body, state_id: 1, project_id: project_id})

          :new_prompt ->
            Prompts.create_prompt(%{title: title, body: body, project_id: project_id})

          _ ->
            {:error, :unknown}
        end

      case result do
        {:ok, _} ->
          socket = assign(socket, :rail_modal, nil)

          socket =
            case modal_type do
              :new_task ->
                assign(socket, :flyout_tasks,
                  Loader.load_flyout_tasks(
                    socket.assigns.sidebar_project,
                    socket.assigns.task_search,
                    socket.assigns.task_state_filter
                  )
                )

              _ ->
                socket
            end

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to create")}
      end
    end
  end

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

  @impl true
  def handle_async(:pick_folder, {:ok, result}, socket),
    do: ProjectActions.handle_pick_folder(result, socket)

  def handle_async(:pick_folder, _result, socket),
    do: ProjectActions.handle_pick_folder(:cancelled, socket)

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="app-rail"
      phx-hook="RailState"
      phx-target={@myself}
      data-project-id={@sidebar_project && @sidebar_project.id}
      class="flex flex-row h-full min-w-0 relative"
    >
      <div
        :if={@mobile_open && @flyout_open}
        phx-click="close_flyout"
        phx-target={@myself}
        class="md:hidden fixed inset-0 z-40 bg-black/40"
      />

      <nav class="w-[52px] flex-shrink-0 flex flex-col items-center py-2 gap-1 border-r border-base-content/8 bg-base-100 z-20">
        <%!-- Tauri overlay titlebar: spacer clears traffic lights + is the window drag region --%>
        <div data-tauri-drag-region aria-hidden="true" class="w-full flex-shrink-0 hidden" />
        <button
          phx-click="toggle_proj_picker"
          phx-target={@myself}
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

        <.rail_item section={:files} active_section={@active_section} flyout_open={@flyout_open} icon="hero-folder" label="Files" myself={@myself} />
        <.rail_item section={:sessions} active_section={@active_section} flyout_open={@flyout_open} icon="lucide-bot-message-square" label="Sessions" myself={@myself} />
        <.rail_item section={:tasks} active_section={@active_section} flyout_open={@flyout_open} icon="hero-check-circle" label="Tasks" myself={@myself} />
        <.rail_item section={:notes} active_section={@active_section} flyout_open={@flyout_open} icon="hero-pencil-square" label="Notes" myself={@myself} />
        <.rail_item section={:agents} active_section={@active_section} flyout_open={@flyout_open} icon="lucide-robot" label="Agents" myself={@myself} />
        <.rail_item section={:skills} active_section={@active_section} flyout_open={@flyout_open} icon="hero-bolt" label="Skills" myself={@myself} />
        <.rail_item section={:prompts} active_section={@active_section} flyout_open={@flyout_open} icon="hero-document-text" label="Prompts" myself={@myself} />
        <.rail_item section={:teams} active_section={@active_section} flyout_open={@flyout_open} icon="hero-users" label="Teams" myself={@myself} />
        <.rail_item section={:jobs} active_section={@active_section} flyout_open={@flyout_open} icon="hero-clock" label="Jobs" myself={@myself} />
        <.rail_item section={:canvas} active_section={@active_section} flyout_open={@flyout_open} icon="hero-squares-2x2" label="Canvas" myself={@myself} />
        <.rail_item section={:chat} active_section={@active_section} flyout_open={@flyout_open} icon="hero-chat-bubble-left-ellipsis" label="Chat" myself={@myself} />
        <.rail_item section={:usage} active_section={@active_section} flyout_open={@flyout_open} icon="hero-chart-bar" label="Usage" myself={@myself} />

        <div class="flex-1" />

        <.link navigate="/notifications" class={["relative w-8 h-8 flex items-center justify-center rounded-lg transition-colors", "text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8"]} aria-label="Notifications">
          <.icon name="hero-bell-mini" class="size-4" />
          <span :if={@notification_count > 0} class="absolute -top-0.5 -right-0.5 min-w-[14px] h-[14px] bg-error text-white text-nano font-bold rounded-full flex items-center justify-center px-0.5">
            {@notification_count}
          </span>
        </.link>

        <.link navigate="/settings" class="w-8 h-8 flex items-center justify-center rounded-lg text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors" aria-label="Settings">
          <.icon name="hero-cog-6-tooth-mini" class="size-4" />
        </.link>

        <.link href="/auth/logout" method="delete" class="w-8 h-8 flex items-center justify-center rounded-lg text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors" aria-label="Sign out">
          <.icon name="hero-arrow-left-on-rectangle-mini" class="size-4" />
        </.link>
      </nav>

      <.project_switcher
        :if={@proj_picker_open}
        projects={@projects}
        sidebar_project={@sidebar_project}
        open={@proj_picker_open}
        new_project_path={@new_project_path}
        myself={@myself}
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
        rail_modal={@rail_modal}
        myself={@myself}
      />

      <.file_panel file_tabs={@file_tabs} active_tab_path={@active_tab_path} myself={@myself} socket={@socket} />
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
      ></div>

      <.live_component
        module={NewSessionModal}
        id="rail-new-session-modal"
        show={@show_new_session_form}
        projects={@projects}
        current_project={@sidebar_project}
        toggle_event="toggle_new_session_drawer"
        submit_event="create_new_session"
        target={@myself}
        prefill_agent_slug={@prefill_agent_slug}
        prefill_agent_name={@prefill_agent_name}
      />
    </div>
    """
  end
end
