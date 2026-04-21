defmodule EyeInTheSkyWeb.Components.Rail do
  @moduledoc false
  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.Components.Rail.Flyout
  import EyeInTheSkyWeb.Components.Rail.ProjectSwitcher, only: [project_switcher: 1]
  import EyeInTheSkyWeb.Components.Rail.Helpers, only: [project_initial: 1]

  alias EyeInTheSky.{Canvases, Channels, Notifications, Projects, Sessions, Teams}
  alias EyeInTheSkyWeb.Components.Rail.ProjectActions

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
    usage: :sessions,
    config: :sessions,
    jobs: :sessions,
    settings: :sessions,
    agents: :sessions,
    files: :sessions,
    bookmarks: :sessions
  }

  @valid_sections ~w(sessions tasks prompts chat notes skills teams canvas notifications)
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
        flyout_canvases: [],
        flyout_teams: [],
        session_filter_open: false,
        session_sort: :last_activity,
        session_name_filter: ""
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

    previous_tab = socket.assigns[:sidebar_tab]
    next_section = Map.get(@section_map, sidebar_tab, :sessions)

    previous_project = socket.assigns[:sidebar_project]

    socket =
      socket
      |> assign(:sidebar_tab, sidebar_tab)
      |> assign(:sidebar_project, sidebar_project)
      |> assign(:active_channel_id, active_channel_id)

    # Only reload flyout sessions when the project actually changes — not on every
    # parent re-render. Every PubSub broadcast through the parent would otherwise
    # fire a Sessions.list_sessions_filtered query on each page.
    socket =
      if sidebar_project != previous_project do
        assign(socket, :flyout_sessions, load_flyout_sessions(sidebar_project, socket.assigns.session_sort, socket.assigns.session_name_filter))
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
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_section", %{"section" => section_str}, socket) do
    section = parse_section(section_str)
    current = socket.assigns.active_section

    if current == section && socket.assigns.flyout_open && not sticky_section?(section) do
      {:noreply, assign(socket, flyout_open: false, mobile_open: false)}
    else
      {:noreply,
       socket
       |> assign(:active_section, section)
       |> assign(:flyout_open, true)
       |> assign(:mobile_open, true)
       |> assign(:proj_picker_open, false)
       |> assign(:flyout_sessions, load_flyout_sessions(socket.assigns.sidebar_project, socket.assigns.session_sort, socket.assigns.session_name_filter))
       |> maybe_load_channels(section, socket.assigns.sidebar_project)
       |> maybe_load_canvases(section)
       |> maybe_load_teams(section, socket.assigns.sidebar_project)}
    end
  end

  def handle_event("close_flyout", _params, socket),
    do: {:noreply, assign(socket, flyout_open: false, mobile_open: false)}

  def handle_event("restore_section", %{"section" => section_str}, socket),
    do: {:noreply, assign(socket, :active_section, parse_section(section_str))}

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
        assign(socket2, :flyout_sessions, load_flyout_sessions(new_project, socket2.assigns.session_sort, socket2.assigns.session_name_filter))
      else
        socket2
      end

    {:noreply, assign(socket3, :proj_picker_open, false)}
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

  def handle_event("toggle_session_filter", _params, socket),
    do: {:noreply, assign(socket, :session_filter_open, !socket.assigns.session_filter_open)}

  def handle_event("set_session_sort", %{"sort" => sort_str}, socket) do
    sort = parse_session_sort(sort_str)
    sessions = load_flyout_sessions(socket.assigns.sidebar_project, sort, socket.assigns.session_name_filter)
    {:noreply, socket |> assign(:session_sort, sort) |> assign(:flyout_sessions, sessions)}
  end

  def handle_event("update_session_name_filter", %{"value" => value}, socket) do
    sessions = load_flyout_sessions(socket.assigns.sidebar_project, socket.assigns.session_sort, value)
    {:noreply, socket |> assign(:session_name_filter, value) |> assign(:flyout_sessions, sessions)}
  end

  @impl true
  def handle_async(:pick_folder, {:ok, result}, socket),
    do: ProjectActions.handle_pick_folder(result, socket)

  def handle_async(:pick_folder, _result, socket),
    do: ProjectActions.handle_pick_folder(:cancelled, socket)

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
      class="flex flex-row h-full relative"
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

        <.rail_item section={:sessions} active_section={@active_section} flyout_open={@flyout_open} icon="hero-cpu-chip" label="Sessions" myself={@myself} />
        <.rail_item section={:tasks} active_section={@active_section} flyout_open={@flyout_open} icon="hero-clipboard-document-list" label="Tasks" myself={@myself} />
        <.rail_item section={:prompts} active_section={@active_section} flyout_open={@flyout_open} icon="hero-chat-bubble-left-right" label="Prompts" myself={@myself} />
        <%= if @sidebar_tab == :chat do %>
          <.rail_item section={:chat} active_section={@active_section} flyout_open={@flyout_open} icon="hero-chat-bubble-left-ellipsis" label="Chat" myself={@myself} />
        <% else %>
          <.link
            navigate="/chat"
            title="Chat"
            aria-label="Chat"
            class="w-8 h-8 flex items-center justify-center rounded-lg transition-colors text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8"
          >
            <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4" />
          </.link>
        <% end %>
        <.rail_item section={:notes} active_section={@active_section} flyout_open={@flyout_open} icon="hero-document-text" label="Notes" myself={@myself} />
        <.rail_item section={:skills} active_section={@active_section} flyout_open={@flyout_open} icon="hero-bolt" label="Skills" myself={@myself} />
        <.rail_item section={:teams} active_section={@active_section} flyout_open={@flyout_open} icon="hero-users" label="Teams" myself={@myself} />
        <%= if @sidebar_tab in [:canvas, :canvases] do %>
          <.rail_item section={:canvas} active_section={@active_section} flyout_open={@flyout_open} icon="hero-squares-2x2" label="Canvas" myself={@myself} />
        <% else %>
          <.link
            navigate="/canvases"
            title="Canvas"
            aria-label="Canvas"
            class="w-8 h-8 flex items-center justify-center rounded-lg transition-colors text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8"
          >
            <.icon name="hero-squares-2x2" class="w-4 h-4" />
          </.link>
        <% end %>

        <div class="flex-1" />

        <.link navigate="/notifications" class={["relative w-8 h-8 flex items-center justify-center rounded-lg transition-colors", "text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8"]} aria-label="Notifications">
          <.icon name="hero-bell-mini" class="w-4 h-4" />
          <span :if={@notification_count > 0} class="absolute -top-0.5 -right-0.5 min-w-[14px] h-[14px] bg-error text-white text-[9px] font-bold rounded-full flex items-center justify-center px-0.5">
            {@notification_count}
          </span>
        </.link>

        <.link navigate="/settings" class="w-8 h-8 flex items-center justify-center rounded-lg text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors" aria-label="Settings">
          <.icon name="hero-cog-6-tooth-mini" class="w-4 h-4" />
        </.link>

        <.link href="/auth/logout" method="delete" class="w-8 h-8 flex items-center justify-center rounded-lg text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors" aria-label="Sign out">
          <.icon name="hero-arrow-left-on-rectangle-mini" class="w-4 h-4" />
        </.link>
      </nav>

      <.project_switcher
        :if={@proj_picker_open}
        projects={@projects}
        sidebar_project={@sidebar_project}
        open={@proj_picker_open}
        new_project_path={@new_project_path}
        myself={@myself}
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
        session_filter_open={@session_filter_open}
        session_sort={@session_sort}
        session_name_filter={@session_name_filter}
        notification_count={@notification_count}
        myself={@myself}
      />
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
      <.icon name={@icon} class="w-4 h-4" />
    </button>
    """
  end

  # Load canvases (with sessions) only when navigating to the :canvas section.
  defp maybe_load_canvases(socket, :canvas) do
    canvases = Canvases.list_canvases_preloaded()

    session_ids =
      canvases
      |> Enum.flat_map(& Enum.map(&1.canvas_sessions, fn cs -> cs.session_id end))
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
