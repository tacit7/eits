defmodule EyeInTheSkyWeb.Components.Rail do
  @moduledoc false
  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.Components.Rail.Flyout
  import EyeInTheSkyWeb.Components.Rail.ProjectSwitcher, only: [project_switcher: 1]
  import EyeInTheSkyWeb.Components.Rail.Helpers, only: [project_initial: 1]

  alias EyeInTheSky.{
    Canvases,
    Channels,
    Notes,
    Notifications,
    Projects,
    ScheduledJobs,
    Sessions,
    Tasks,
    Teams
  }

  alias EyeInTheSky.Projects.FileTree
  alias EyeInTheSkyWeb.Components.Rail.FileActions
  alias EyeInTheSkyWeb.Components.Rail.ProjectActions
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
    agents: :sessions,
    files: :files,
    bookmarks: :sessions
  }

  @valid_sections ~w(sessions tasks prompts chat notes skills teams canvas notifications usage jobs files)
  @sticky_sections [:chat, :canvas]

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
        flyout_tasks: [],
        task_search: "",
        task_state_filter: nil,
        task_filter_open: false,
        session_filter_open: false,
        session_sort: :last_activity,
        session_name_filter: "",
        flyout_notes: [],
        flyout_jobs: [],
        flyout_file_nodes: [],
        flyout_file_expanded: MapSet.new(),
        flyout_file_children: %{},
        flyout_file_error: nil,
        file_tabs: [],
        active_tab_path: nil,
        show_new_session_form: false
      )

    # Skip DB queries on the dead render (mount runs twice — static + connected).
    # This component mounts on every page, so the unguarded path doubles DB load.
    if connected?(socket) do
      {:ok,
       assign(socket,
         projects: Projects.list_projects_for_sidebar(),
         flyout_sessions: load_flyout_sessions(nil),
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

  def update(%{refresh_projects: true}, socket) do
    {:ok, assign(socket, :projects, Projects.list_projects_for_sidebar())}
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
          load_flyout_sessions(
            sidebar_project,
            socket.assigns.session_sort,
            socket.assigns.session_name_filter
          )
        )
        |> assign(:flyout_file_expanded, MapSet.new())
        |> assign(:flyout_file_children, %{})
        |> maybe_load_files(socket.assigns.active_section)
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
        |> maybe_load_channels(next_section, sidebar_project)
        |> maybe_load_canvases(next_section)
        |> maybe_load_teams(next_section, sidebar_project)
        |> maybe_load_tasks(next_section, sidebar_project)
        |> maybe_load_jobs(next_section)
        |> maybe_load_notes(next_section, sidebar_project)
        |> maybe_load_files(next_section)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_section", %{"section" => section_str}, socket) do
    section = parse_section(section_str)
    current = socket.assigns.active_section

    sticky = sticky_section(socket.assigns.sidebar_tab)

    if current == section && socket.assigns.flyout_open && not sticky_section?(section) do
      if sticky do
        {:noreply,
         socket
         |> assign(:active_section, sticky)
         |> assign(:flyout_open, true)
         |> assign(:mobile_open, false)}
      else
        {:noreply, assign(socket, flyout_open: false, mobile_open: false)}
      end
    else
      {:noreply,
       socket
       |> assign(:active_section, section)
       |> assign(:flyout_open, true)
       |> assign(:mobile_open, true)
       |> assign(:proj_picker_open, false)
       |> assign(
         :flyout_sessions,
         load_flyout_sessions(
           socket.assigns.sidebar_project,
           socket.assigns.session_sort,
           socket.assigns.session_name_filter
         )
       )
       |> maybe_load_channels(section, socket.assigns.sidebar_project)
       |> maybe_load_canvases(section)
       |> maybe_load_teams(section, socket.assigns.sidebar_project)
       |> maybe_load_tasks(section, socket.assigns.sidebar_project)
       |> maybe_load_jobs(section)
       |> maybe_load_notes(section, socket.assigns.sidebar_project)
       |> maybe_load_files(section)}
    end
  end

  def handle_event("close_flyout", _params, socket) do
    case sticky_section(socket.assigns.sidebar_tab) do
      nil ->
        {:noreply, assign(socket, flyout_open: false, mobile_open: false)}

      sticky ->
        {:noreply,
         socket
         |> assign(:active_section, sticky)
         |> assign(:flyout_open, true)
         |> assign(:mobile_open, false)}
    end
  end

  def handle_event("restore_section", %{"section" => section_str}, socket),
    do: {:noreply, assign(socket, :active_section, parse_section(section_str))}

  # Restore the last selected project from localStorage after a cross-LiveView navigation.
  # Only applies when the parent has not already provided a project (sidebar_project is nil).
  # Project-scoped pages set sidebar_project in update/2 before the hook fires, so we
  # skip the restore in that case to avoid overriding the route-derived context.
  def handle_event("restore_project", %{"project_id" => id_str}, socket)
      when is_nil(socket.assigns.sidebar_project) do
    case EyeInTheSkyWeb.ControllerHelpers.parse_int(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        case Projects.get_project(id) do
          {:ok, project} ->
            socket =
              socket
              |> assign(:sidebar_project, project)
              |> assign(
                :flyout_sessions,
                load_flyout_sessions(
                  project,
                  socket.assigns.session_sort,
                  socket.assigns.session_name_filter
                )
              )

            {:noreply, socket}

          {:error, _} ->
            # Project was deleted or inaccessible — clear the stale localStorage entry
            {:noreply, push_event(socket, "save_project", %{project_id: nil})}
        end
    end
  end

  def handle_event("restore_project", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_proj_picker", _params, socket),
    do: {:noreply, assign(socket, :proj_picker_open, !socket.assigns.proj_picker_open)}

  def handle_event("close_proj_picker", _params, socket),
    do: {:noreply, assign(socket, :proj_picker_open, false)}

  def handle_event("open_mobile", _params, socket),
    do: {:noreply, assign(socket, mobile_open: true, flyout_open: true)}

  def handle_event("select_project", params, socket) do
    previous_project = socket.assigns.sidebar_project
    {:noreply, socket2} = ProjectActions.handle_select_project(params, socket)
    new_project = socket2.assigns.sidebar_project

    socket3 =
      if new_project != previous_project do
        socket2
        |> assign(
          :flyout_sessions,
          load_flyout_sessions(
            new_project,
            socket2.assigns.session_sort,
            socket2.assigns.session_name_filter
          )
        )
        |> assign(:flyout_file_expanded, MapSet.new())
        |> assign(:flyout_file_children, %{})
        |> maybe_load_files(socket2.assigns.active_section)
      else
        socket2
      end

    # Persist the selected project_id to localStorage via the RailState hook so it
    # survives cross-LiveView navigation (where the LiveComponent remounts).
    project_id = new_project && new_project.id
    socket4 = push_event(socket3, "save_project", %{project_id: project_id})

    {:noreply, socket4 |> assign(:proj_picker_open, false) |> assign(:scope_type, :project)}
  end

  def handle_event("select_workspace", _params, socket) do
    socket =
      socket
      |> assign(:proj_picker_open, false)
      |> assign(:sidebar_project, nil)
      |> assign(:scope_type, :workspace)
      |> push_navigate(to: ~p"/workspace/sessions")

    {:noreply, socket}
  end

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

  def handle_event("create_new_session", params, socket),
    do: IndexActions.handle_create_new_session(params, socket)

  def handle_event("toggle_session_filter", _params, socket),
    do: {:noreply, assign(socket, :session_filter_open, !socket.assigns.session_filter_open)}

  def handle_event("set_session_sort", %{"sort" => sort_str}, socket) do
    sort = parse_session_sort(sort_str)

    sessions =
      load_flyout_sessions(
        socket.assigns.sidebar_project,
        sort,
        socket.assigns.session_name_filter
      )

    {:noreply, socket |> assign(:session_sort, sort) |> assign(:flyout_sessions, sessions)}
  end

  def handle_event("update_session_name_filter", %{"value" => value}, socket) do
    sessions =
      load_flyout_sessions(socket.assigns.sidebar_project, socket.assigns.session_sort, value)

    {:noreply,
     socket |> assign(:session_name_filter, value) |> assign(:flyout_sessions, sessions)}
  end

  def handle_event("toggle_task_filter", _params, socket),
    do: {:noreply, assign(socket, :task_filter_open, !socket.assigns.task_filter_open)}

  def handle_event("update_task_search", %{"value" => value}, socket) do
    tasks =
      load_flyout_tasks(socket.assigns.sidebar_project, value, socket.assigns.task_state_filter)

    {:noreply, socket |> assign(:task_search, value) |> assign(:flyout_tasks, tasks)}
  end

  def handle_event("set_task_state_filter", %{"state" => state_str}, socket) do
    state_id = parse_task_state(state_str)

    tasks =
      load_flyout_tasks(socket.assigns.sidebar_project, socket.assigns.task_search, state_id)

    {:noreply, socket |> assign(:task_state_filter, state_id) |> assign(:flyout_tasks, tasks)}
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

  @impl true
  def handle_async(:pick_folder, {:ok, result}, socket),
    do: ProjectActions.handle_pick_folder(result, socket)

  def handle_async(:pick_folder, _result, socket),
    do: ProjectActions.handle_pick_folder(:cancelled, socket)

  # Returns the section that should always remain visible for a given page.
  # nil means the flyout can be fully closed.
  defp sticky_section(sidebar_tab) when sidebar_tab in [:canvas, :canvases], do: :canvas
  defp sticky_section(:chat), do: :chat
  defp sticky_section(_), do: nil

  defp parse_section(section_str) when section_str in @valid_sections,
    do: String.to_existing_atom(section_str)

  defp parse_section(_), do: :sessions

  defp load_flyout_sessions(project, sort \\ :last_activity, name_filter \\ "") do
    opts = [limit: 15, status_filter: "all", sort_by: sort]
    opts = if project, do: Keyword.put(opts, :project_id, project.id), else: opts
    opts = if name_filter != "", do: Keyword.put(opts, :name_filter, name_filter), else: opts

    case Sessions.list_sessions_filtered(opts) do
      sessions when is_list(sessions) -> sessions
      {:ok, sessions} when is_list(sessions) -> sessions
      _ -> []
    end
  end

  defp parse_session_sort("created"), do: :created
  defp parse_session_sort("name"), do: :name
  defp parse_session_sort(_), do: :last_activity

  defp sticky_section?(section), do: section in @sticky_sections

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
        <.rail_item section={:sessions} active_section={@active_section} flyout_open={@flyout_open} icon="lucide-robot" label="Sessions" myself={@myself} />
        <.rail_item section={:tasks} active_section={@active_section} flyout_open={@flyout_open} icon="hero-check-circle" label="Tasks" myself={@myself} />
        <.rail_item section={:notes} active_section={@active_section} flyout_open={@flyout_open} icon="hero-pencil-square" label="Notes" myself={@myself} />
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
        flyout_canvases={@flyout_canvases}
        flyout_teams={@flyout_teams}
        flyout_tasks={@flyout_tasks}
        task_search={@task_search}
        task_state_filter={@task_state_filter}
        task_filter_open={@task_filter_open}
        session_filter_open={@session_filter_open}
        session_sort={@session_sort}
        session_name_filter={@session_name_filter}
        notification_count={@notification_count}
        flyout_notes={@flyout_notes}
        flyout_jobs={@flyout_jobs}
        flyout_file_nodes={@flyout_file_nodes}
        flyout_file_expanded={@flyout_file_expanded}
        flyout_file_children={@flyout_file_children}
        flyout_file_error={@flyout_file_error}
        myself={@myself}
      />

      <.file_panel file_tabs={@file_tabs} active_tab_path={@active_tab_path} myself={@myself} socket={@socket} />
      <%!-- Splitter handle for split-view mode. Visibility driven by data-editor-mode on <html>. --%>
      <div id="editor-splitter" aria-hidden="true"></div>

      <.live_component
        module={NewSessionModal}
        id="rail-new-session-modal"
        show={@show_new_session_form}
        projects={@projects}
        current_project={@sidebar_project}
        toggle_event="toggle_new_session_drawer"
        submit_event="create_new_session"
        target={@myself}
      />
    </div>
    """
  end

  attr :file_tabs, :list, required: true
  attr :active_tab_path, :any, required: true
  attr :myself, :any, required: true
  attr :socket, :any, required: true

  defp file_panel(assigns) do
    active_tab = Enum.find(assigns.file_tabs, &(&1.path == assigns.active_tab_path))
    assigns = assign(assigns, :active_tab, active_tab)

    ~H"""
    <div
      id="file-editor-pane"
      phx-hook="EditorLayout"
      data-has-tabs={if @file_tabs == [], do: "false", else: "true"}
      class="min-w-0 flex-col border-l border-base-content/8 bg-base-100 overflow-hidden"
    >
      <%!-- Tab strip + toolbar --%>
      <div class="flex items-center border-b border-base-content/8 bg-base-200/40 flex-shrink-0 min-h-[32px]">
        <div class="flex-1 flex items-center overflow-x-auto">
          <%= for tab <- @file_tabs do %>
            <% active = tab.path == @active_tab_path %>
            <div class={[
              "flex items-center border-r border-base-content/8 flex-shrink-0",
              if(active, do: "bg-base-100", else: "bg-transparent")
            ]}>
              <button
                phx-click="file_switch_tab"
                phx-value-path={tab.path}
                phx-target={@myself}
                class={[
                  "px-3 py-1.5 text-xs truncate max-w-[160px]",
                  if(active, do: "text-base-content/90 font-medium", else: "text-base-content/45 hover:text-base-content/70")
                ]}
                title={tab.path}
              >
                {tab.name}
              </button>
              <button
                phx-click="file_close_tab"
                phx-value-path={tab.path}
                phx-target={@myself}
                class="pr-2 py-1.5 text-base-content/25 hover:text-base-content/60 transition-colors"
                title="Close"
              >
                <.icon name="hero-x-mark-mini" class="size-3" />
              </button>
            </div>
          <% end %>
        </div>
        <%!-- Split-mode toggle. Hidden unless current page allows split (CSS rule
             keyed off body[data-allow-split]). Click dispatches a window event
             handled by the EditorLayout hook. --%>
        <button
          type="button"
          phx-click={Phoenix.LiveView.JS.dispatch("editor:toggle-split", to: "window")}
          class="px-2 py-1.5 text-base-content/45 hover:text-base-content/80 transition-colors flex-shrink-0 items-center"
          data-editor-toggle
          title="Toggle split view"
          aria-label="Toggle split view"
        >
          <.icon name="hero-view-columns" class="size-4" />
        </button>
      </div>

      <%!-- Editor area or empty state --%>
      <%= if @active_tab do %>
        <div id="file-editor-relay" phx-hook="FileEditorRelay" class="hidden" />
        <%!--
          [&>div]:h-full punches height into the LiveSvelte wrapper div, which is
          auto-height by default. Without it the editor collapses to 0 height since
          the Svelte root's h-full has no anchor.
        --%>
        <div
          id={"file-editor-#{Base.url_encode64(@active_tab.path, padding: false)}"}
          phx-update="ignore"
          class="flex-1 min-w-0 overflow-hidden [&>div]:h-full"
        >
          <.svelte
            name="FileEditor"
            ssr={false}
            props={%{
              content: @active_tab.content,
              lang: @active_tab.language,
              path: @active_tab.path,
              hash: @active_tab.hash
            }}
            socket={@socket}
          />
        </div>
      <% else %>
        <div class="flex-1 flex flex-col items-center justify-center p-6 text-center text-sm text-base-content/50">
          <.icon name="hero-document-text" class="w-8 h-8 mb-2 opacity-40" />
          <p class="font-medium text-base-content/70">No file selected</p>
          <p class="mt-1">Choose a file from the file explorer to open it here.</p>
        </div>
      <% end %>
    </div>
    """
  end

  attr :section, :atom, required: true
  attr :active_section, :atom, required: true
  attr :flyout_open, :boolean, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :myself, :any, required: true

  defp rail_item(assigns) do
    ~H"""
    <button
      phx-click="toggle_section"
      phx-value-section={@section}
      phx-target={@myself}
      title={@label}
      aria-label={@label}
      class={[
        "w-8 h-8 flex items-center justify-center rounded-lg transition-colors",
        if(@active_section == @section && @flyout_open,
          do: "bg-primary/15 text-primary",
          else: "text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8"
        )
      ]}
    >
      <%= if String.starts_with?(@icon, "lucide-") do %>
        <.custom_icon name={@icon} class="size-4" />
      <% else %>
        <.icon name={@icon} class="size-4" />
      <% end %>
    </button>
    """
  end

  # Load canvases (with sessions) only when navigating to the :canvas section.
  defp maybe_load_canvases(socket, :canvas) do
    canvases = Canvases.list_canvases_preloaded()

    session_ids =
      canvases
      |> Enum.flat_map(&Enum.map(&1.canvas_sessions, fn cs -> cs.session_id end))
      |> Enum.uniq()

    sessions_by_id =
      Sessions.list_sessions_by_ids(session_ids)
      |> Map.new(fn s -> {s.id, s} end)

    flyout_canvases =
      Enum.map(canvases, fn canvas ->
        sessions =
          canvas.canvas_sessions
          |> Enum.map(fn cs -> sessions_by_id[cs.session_id] end)
          |> Enum.reject(&is_nil/1)

        %{id: canvas.id, name: canvas.name, sessions: sessions}
      end)

    assign(socket, :flyout_canvases, flyout_canvases)
  end

  defp maybe_load_canvases(socket, _section), do: socket

  defp maybe_load_teams(socket, :teams, project) do
    opts = if project, do: [project_id: project.id], else: []
    teams = Teams.list_teams(opts)
    assign(socket, :flyout_teams, teams)
  end

  defp maybe_load_teams(socket, _section, _project), do: socket

  defp maybe_load_tasks(socket, :tasks, project) do
    tasks =
      load_flyout_tasks(
        project,
        socket.assigns[:task_search] || "",
        socket.assigns[:task_state_filter]
      )

    assign(socket, :flyout_tasks, tasks)
  end

  defp maybe_load_tasks(socket, _section, _project), do: socket

  defp maybe_load_jobs(socket, :jobs) do
    jobs = ScheduledJobs.list_jobs() |> Enum.take(15)
    assign(socket, :flyout_jobs, jobs)
  end

  defp maybe_load_jobs(socket, _section), do: socket

  defp maybe_load_notes(socket, :notes, project) do
    opts = [limit: 20]
    opts = if project, do: Keyword.put(opts, :project_id, project.id), else: opts
    assign(socket, :flyout_notes, Notes.list_notes_filtered(opts))
  end

  defp maybe_load_notes(socket, _section, _project), do: socket

  defp maybe_load_files(socket, :files) do
    project = socket.assigns.sidebar_project

    if project && project.path do
      case FileTree.root(project.path) do
        {:ok, nodes} ->
          socket
          |> assign(:flyout_file_nodes, nodes)
          |> assign(:flyout_file_error, nil)

        {:error, reason} ->
          socket
          |> assign(:flyout_file_nodes, [])
          |> assign(:flyout_file_error, file_error_message(reason))
      end
    else
      socket
      |> assign(:flyout_file_nodes, [])
      |> assign(:flyout_file_error, "No project path configured")
    end
  end

  defp maybe_load_files(socket, _section), do: socket

  defp file_error_message(:root_path_not_found), do: "Project directory not found"
  defp file_error_message(:root_path_not_directory), do: "Project path is not a directory"
  defp file_error_message(:permission_denied), do: "Permission denied"
  defp file_error_message(:path_not_found), do: "Directory not found"
  defp file_error_message(:symlink_escapes_project), do: "Path escapes project root"
  defp file_error_message(_), do: "Cannot read directory"

  defp load_flyout_tasks(project, search, state_id) do
    project_id = project && project.id
    state_opts = if state_id, do: [state_id: state_id], else: []

    cond do
      search != "" ->
        Tasks.search_tasks(search, project_id, [limit: 50] ++ state_opts)

      project_id ->
        Tasks.list_tasks_for_project(
          project_id,
          [limit: 50, sort_by: "created_desc"] ++ state_opts
        )

      true ->
        Tasks.list_tasks([limit: 50, sort_by: "created_desc"] ++ state_opts)
    end
  end

  defp parse_task_state("1"), do: 1
  defp parse_task_state("2"), do: 2
  defp parse_task_state("3"), do: 3
  defp parse_task_state("4"), do: 4
  defp parse_task_state(_), do: nil

  # Load channels only when navigating to the :chat section — avoids a DB query on every page.
  defp maybe_load_channels(socket, :chat, project) do
    project_id = project && project.id

    channels =
      case Channels.list_channels_for_project(project_id) do
        list when is_list(list) -> list
        _ -> []
      end

    assign(socket, :flyout_channels, channels)
  end

  defp maybe_load_channels(socket, _section, _project), do: socket
end
