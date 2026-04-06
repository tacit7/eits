defmodule EyeInTheSkyWeb.Components.Sidebar do
  @moduledoc false
  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.Components.Sidebar.SystemSection
  import EyeInTheSkyWeb.Components.Sidebar.ChatSection
  import EyeInTheSkyWeb.Components.Sidebar.ProjectsSection

  alias EyeInTheSky.{Channels, Notifications, Projects}
  alias EyeInTheSkyWeb.Components.Sidebar.{ChannelActions, ProjectActions}

  @impl true
  def mount(socket) do
    projects = Projects.list_projects_for_sidebar()

    channels =
      case Channels.list_channels() do
        channels when is_list(channels) -> channels
        _ -> []
      end

    {:ok,
     assign(socket,
       projects: projects,
       channels: channels,
       collapsed: false,
       mobile_open: false,
       expanded_all_projects: true,
       expanded_projects: true,
       expanded_system: true,
       expanded_chat: false,
       new_channel_name: nil,
       new_project_path: nil,
       notification_count: Notifications.unread_count(),
       renaming_project_id: nil,
       rename_value: ""
     )}
  end

  @impl true
  def update(%{notification_count: :refresh}, socket) do
    {:ok, assign(socket, :notification_count, Notifications.unread_count())}
  end

  def update(%{refresh_projects: true}, socket) do
    {:ok, assign(socket, :projects, Projects.list_projects_for_sidebar())}
  end

  def update(assigns, socket) do
    # Parent sets sidebar_project when on a project route; otherwise nil.
    # Prefer the parent value when present; keep the locally-pinned project
    # (set via select_project click) when the parent has none.
    sidebar_project =
      assigns[:sidebar_project] || socket.assigns[:sidebar_project]

    # Auto-expand chat when on chat page
    sidebar_tab = assigns[:sidebar_tab] || :sessions
    expanded_chat = if sidebar_tab == :chat, do: true, else: socket.assigns.expanded_chat

    {:ok,
     socket
     |> assign(:sidebar_tab, sidebar_tab)
     |> assign(:sidebar_project, sidebar_project)
     |> assign(:active_channel_id, assigns[:active_channel_id])
     |> assign(:expanded_chat, expanded_chat)
     |> assign(:mobile_open, false)
     |> assign(:expanded_all_projects, socket.assigns[:expanded_all_projects] != false)
     |> assign(:expanded_projects, socket.assigns[:expanded_projects] != false)
     |> assign(:expanded_system, socket.assigns[:expanded_system] != false)}
  end

  # --- Navigation ---

  @impl true
  def handle_event("new_chat", _params, socket),
    do: {:noreply, push_navigate(socket, to: "/?new=1")}

  # --- UI toggles ---

  @impl true
  def handle_event("toggle_collapsed", _params, socket),
    do: {:noreply, assign(socket, :collapsed, !socket.assigns.collapsed)}

  @impl true
  def handle_event("toggle_mobile", _params, socket),
    do: {:noreply, assign(socket, :mobile_open, !socket.assigns.mobile_open)}

  @impl true
  def handle_event("open_mobile", _params, socket),
    do: {:noreply, assign(socket, :mobile_open, true)}

  @impl true
  def handle_event("close_mobile", _params, socket),
    do: {:noreply, assign(socket, :mobile_open, false)}

  @impl true
  def handle_event("toggle_all_projects", _params, socket),
    do: {:noreply, assign(socket, :expanded_all_projects, !socket.assigns.expanded_all_projects)}

  @impl true
  def handle_event("toggle_projects", _params, socket),
    do: {:noreply, assign(socket, :expanded_projects, !socket.assigns.expanded_projects)}

  @impl true
  def handle_event("toggle_system", _params, socket),
    do: {:noreply, assign(socket, :expanded_system, !socket.assigns.expanded_system)}

  @impl true
  def handle_event("toggle_chat", _params, socket),
    do: {:noreply, assign(socket, :expanded_chat, !socket.assigns.expanded_chat)}

  # --- Project actions ---

  @impl true
  def handle_event("select_project", params, socket),
    do: ProjectActions.handle_select_project(params, socket)

  @impl true
  def handle_event("new_session", params, socket),
    do: ProjectActions.handle_new_session(params, socket)

  @impl true
  def handle_event("start_rename_project", params, socket),
    do: ProjectActions.handle_start_rename(params, socket)

  @impl true
  def handle_event("cancel_rename_project", _params, socket),
    do: ProjectActions.handle_cancel_rename(socket)

  @impl true
  def handle_event("update_rename_value", params, socket),
    do: ProjectActions.handle_update_rename_value(params, socket)

  @impl true
  def handle_event("commit_rename_project", _params, socket),
    do: ProjectActions.handle_commit_rename(socket)

  @impl true
  def handle_event("delete_project", params, socket),
    do: ProjectActions.handle_delete_project(params, socket)

  @impl true
  def handle_event("set_bookmark", params, socket),
    do: ProjectActions.handle_set_bookmark(params, socket)

  @impl true
  def handle_event("show_new_project", _params, socket),
    do: ProjectActions.handle_show_new_project(socket)

  @impl true
  def handle_event("cancel_new_project", _params, socket),
    do: ProjectActions.handle_cancel_new_project(socket)

  @impl true
  def handle_event("update_project_path", params, socket),
    do: ProjectActions.handle_update_project_path(params, socket)

  @impl true
  def handle_event("create_project", _params, socket),
    do: ProjectActions.handle_create_project(socket)

  # --- Channel actions ---

  @impl true
  def handle_event("show_new_channel", _params, socket),
    do: ChannelActions.handle_show_new_channel(socket)

  @impl true
  def handle_event("cancel_new_channel", _params, socket),
    do: ChannelActions.handle_cancel_new_channel(socket)

  @impl true
  def handle_event("update_channel_name", params, socket),
    do: ChannelActions.handle_update_channel_name(params, socket)

  @impl true
  def handle_event("create_channel", _params, socket),
    do: ChannelActions.handle_create_channel(socket)

  # --- Async handlers ---

  @impl true
  def handle_async(:pick_folder, {:ok, result}, socket),
    do: ProjectActions.handle_pick_folder(result, socket)

  def handle_async(:pick_folder, _result, socket),
    do: ProjectActions.handle_pick_folder(:cancelled, socket)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Backdrop — mobile only, closes sidebar on tap --%>
      <div
        :if={@mobile_open}
        phx-click="close_mobile"
        phx-target={@myself}
        class="md:hidden fixed inset-0 z-40 bg-black/40"
      />

      <aside
        id="app-sidebar"
        phx-hook="SidebarState"
        phx-target={@myself}
        class={[
          "flex flex-col h-full border-r border-base-content/10 bg-base-100 lg:bg-gradient-to-t lg:from-base-300/5 lg:to-base-300/30 shadow-lg lg:shadow-none transition-[background-color,border-color,box-shadow] duration-[35ms] flex-shrink-0 overflow-hidden safe-inset-y",
          "fixed inset-y-0 left-0 z-50 md:relative md:inset-auto md:z-auto",
          "w-[85vw] max-w-72",
          if(@mobile_open, do: "translate-x-0", else: "-translate-x-full md:translate-x-0"),
          if(@collapsed, do: "md:w-16", else: "md:w-60")
        ]}
      >
        <%!-- Branding --%>
        <div class="flex items-center gap-2 px-3 py-3 border-b border-base-content/5">
          <.link navigate="/" class="flex items-center gap-2 min-w-0 flex-1">
            <img src="/images/logo.svg" class="w-7 h-7 flex-shrink-0" alt="Eye in the Sky" />
            <span class={[
              "text-sm font-semibold text-base-content/80 truncate",
              if(@collapsed, do: "hidden")
            ]}>
              Eye in the Sky
            </span>
          </.link>
          <button
            phx-click="new_chat"
            phx-target={@myself}
            class={[
              "btn btn-ghost btn-xs btn-square text-base-content/40 hover:text-primary hover:bg-primary/10 transition-colors",
              if(@mobile_open, do: "hidden")
            ]}
            title="New Chat"
          >
            <.icon name="hero-pencil-square" class="w-4 h-4" />
          </button>
          <button
            :if={@mobile_open}
            phx-click="close_mobile"
            phx-target={@myself}
            class="md:hidden btn btn-ghost btn-xs btn-square text-base-content/40"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>

        <%!-- Scrollable nav --%>
        <nav class="flex-1 overflow-y-auto overflow-x-hidden py-2 [&::-webkit-scrollbar]:hidden [-ms-overflow-style:none] [scrollbar-width:none]">
          <.all_projects_section
            sidebar_tab={@sidebar_tab}
            sidebar_project={@sidebar_project}
            collapsed={@collapsed}
            expanded_all_projects={@expanded_all_projects}
            notification_count={@notification_count}
            myself={@myself}
          />
          <.chat_section
            sidebar_tab={@sidebar_tab}
            collapsed={@collapsed}
            expanded_chat={@expanded_chat}
            channels={@channels}
            active_channel_id={@active_channel_id}
            new_channel_name={@new_channel_name}
            myself={@myself}
          />
          <.projects_section
            projects={@projects}
            sidebar_project={@sidebar_project}
            sidebar_tab={@sidebar_tab}
            collapsed={@collapsed}
            expanded_projects={@expanded_projects}
            new_project_path={@new_project_path}
            renaming_project_id={@renaming_project_id}
            rename_value={@rename_value}
            myself={@myself}
          />
          <.system_section
            sidebar_tab={@sidebar_tab}
            sidebar_project={@sidebar_project}
            collapsed={@collapsed}
            expanded_system={@expanded_system}
            myself={@myself}
          />
        </nav>

        <%!-- Bottom controls --%>
        <div class="border-t border-base-content/5 p-2 flex items-center gap-2">
          <%= if !@collapsed do %>
            <div class="flex-1">
              <.theme_toggle />
            </div>
          <% end %>
          <.link
            href="/auth/logout"
            method="delete"
            class="btn btn-ghost btn-xs btn-square text-base-content/40 hover:text-red-500"
            title="Sign out"
          >
            <.icon name="hero-arrow-right-on-rectangle-mini" class="w-4 h-4" />
          </.link>
          <button
            phx-click="toggle_collapsed"
            phx-target={@myself}
            class="btn btn-ghost btn-xs btn-square text-base-content/40 hover:text-base-content/70"
            title={if @collapsed, do: "Expand sidebar", else: "Collapse sidebar"}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 20 20"
              fill="currentColor"
              class="w-4 h-4"
            >
              <path d="M16.5 4C17.3284 4 18 4.67157 18 5.5V14.5C18 15.3284 17.3284 16 16.5 16H3.5C2.67157 16 2 15.3284 2 14.5V5.5C2 4.67157 2.67157 4 3.5 4H16.5ZM7 15H16.5C16.7761 15 17 14.7761 17 14.5V5.5C17 5.22386 16.7761 5 16.5 5H7V15ZM3.5 5C3.22386 5 3 5.22386 3 5.5V14.5C3 14.7761 3.22386 15 3.5 15H6V5H3.5Z" />
            </svg>
          </button>
        </div>
      </aside>
    </div>
    """
  end

  attr :sidebar_tab, :atom, required: true
  attr :sidebar_project, :any, default: nil
  attr :collapsed, :boolean, required: true
  attr :expanded_all_projects, :boolean, required: true
  attr :notification_count, :integer, required: true
  attr :myself, :any, required: true

  defp all_projects_section(assigns) do
    ~H"""
    <% overview_active = @sidebar_tab in [:sessions, :tasks, :prompts, :notes, :skills, :teams, :notifications, :usage] && is_nil(@sidebar_project) %>
    <button
      phx-click="toggle_all_projects"
      phx-target={@myself}
      data-section-toggle="overview"
      class={[
        "flex items-center gap-2.5 w-full text-left text-sm transition-colors min-h-[44px]",
        if(@collapsed, do: "px-4 py-2 justify-center", else: "px-3 py-2"),
        if(overview_active,
          do: "text-base-content/80 hover:bg-base-content/5",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5"
        )
      ]}
      title="Overview"
    >
      <%= if !@collapsed do %>
        <.icon
          name={if @expanded_all_projects, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="w-3.5 h-3.5 flex-shrink-0"
        />
      <% end %>
      <.icon name="hero-rectangle-stack" class="w-4 h-4 flex-shrink-0" />
      <span class={["truncate font-medium", if(@collapsed, do: "hidden")]}>Workspace</span>
      <%= if overview_active && !@collapsed do %>
        <span class="ml-auto w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
      <% end %>
    </button>

    <%= if @expanded_all_projects || @collapsed do %>
      <div class={if !@collapsed, do: "ml-5 border-l border-base-content/8"}>
        <.section_sub_item
          href="/"
          icon="hero-cpu-chip"
          label="Sessions"
          active={@sidebar_tab == :sessions && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/tasks"
          icon="hero-clipboard-document-list"
          label="Tasks"
          active={@sidebar_tab == :tasks && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/prompts"
          icon="hero-chat-bubble-left-right"
          label="Prompts"
          active={@sidebar_tab == :prompts && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/notes"
          icon="hero-document-text"
          label="Notes"
          active={@sidebar_tab == :notes && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/skills"
          icon="hero-bolt"
          label="Skills"
          active={@sidebar_tab == :skills}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/teams"
          icon="hero-users"
          label="Teams"
          active={@sidebar_tab == :teams}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/usage"
          icon="hero-chart-bar"
          label="Usage"
          active={@sidebar_tab == :usage}
          collapsed={@collapsed}
        />
        <button
          phx-click="toggle"
          phx-target="#canvas-overlay"
          class={[
            "flex items-center gap-2 text-sm transition-colors w-full min-h-[44px]",
            if(@collapsed, do: "px-4 py-2 justify-center", else: "pl-3 pr-3 py-2"),
            "text-base-content/50 hover:text-base-content/75 hover:bg-base-content/5"
          ]}
          title="Canvas"
        >
          <.icon name="hero-squares-2x2" class="w-3.5 h-3.5 flex-shrink-0" />
          <span class={["truncate", if(@collapsed, do: "hidden")]}>Canvas</span>
        </button>
        <.section_notification_item
          href="/notifications"
          active={@sidebar_tab == :notifications}
          collapsed={@collapsed}
          count={@notification_count}
        />
      </div>
    <% end %>
    """
  end

  defp section_sub_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-2 text-sm transition-colors min-h-[44px]",
        if(@collapsed, do: "px-4 py-2 justify-center", else: "pl-3 pr-3 py-2"),
        if(@active,
          do: "text-primary bg-primary/5 font-medium",
          else: "text-base-content/50 hover:text-base-content/75 hover:bg-base-content/5"
        )
      ]}
      title={@label}
    >
      <.icon name={@icon} class="w-3.5 h-3.5 flex-shrink-0" />
      <span class={["truncate", if(@collapsed, do: "hidden")]}>{@label}</span>
    </.link>
    """
  end

  attr :href, :string, required: true
  attr :active, :boolean, default: false
  attr :collapsed, :boolean, default: false
  attr :count, :integer, default: 0

  defp section_notification_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-2 text-sm transition-colors min-h-[44px]",
        if(@collapsed, do: "px-4 py-2 justify-center", else: "pl-3 pr-3 py-2"),
        if(@active,
          do: "text-primary bg-primary/5 font-medium",
          else: "text-base-content/50 hover:text-base-content/75 hover:bg-base-content/5"
        )
      ]}
      title="Notifications"
    >
      <div class="relative">
        <.icon name="hero-bell" class="w-3.5 h-3.5 flex-shrink-0" />
        <%= if @count > 0 do %>
          <span class="absolute -top-1.5 -right-1.5 badge badge-xs badge-primary text-[9px] min-w-[14px] h-[14px] p-0">
            {if @count > 99, do: "99+", else: @count}
          </span>
        <% end %>
      </div>
      <span class={["truncate", if(@collapsed, do: "hidden")]}>Notifications</span>
    </.link>
    """
  end

  defp theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5 rounded-full bg-base-content/5 p-0.5">
      <button
        class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-full hover:bg-base-content/10 transition-colors"
        phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        title="System theme"
      >
        <.icon name="hero-computer-desktop-micro" class="w-3.5 h-3.5 text-base-content/40" />
      </button>
      <button
        class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-full hover:bg-base-content/10 transition-colors"
        phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light theme"
      >
        <.icon name="hero-sun-micro" class="w-3.5 h-3.5 text-base-content/40" />
      </button>
      <button
        class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-full hover:bg-base-content/10 transition-colors"
        phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark theme"
      >
        <.icon name="hero-moon-micro" class="w-3.5 h-3.5 text-base-content/40" />
      </button>
    </div>
    """
  end
end
