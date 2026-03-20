defmodule EyeInTheSkyWebWeb.Components.Sidebar do
  use EyeInTheSkyWebWeb, :live_component

  alias EyeInTheSkyWeb.{Projects, Channels, Notifications}
  alias EyeInTheSkyWeb.Channels.Channel
  alias EyeInTheSkyWeb.Agents.AgentManager

  @impl true
  def mount(socket) do
    projects = Projects.list_projects()

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

  def update(assigns, socket) do
    sidebar_project = assigns[:sidebar_project]

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

  @impl true
  def handle_event("new_chat", _params, socket) do
    {:noreply, push_navigate(socket, to: "/?new=1")}
  end

  @impl true
  def handle_event("toggle_collapsed", _params, socket) do
    {:noreply, assign(socket, :collapsed, !socket.assigns.collapsed)}
  end

  @impl true
  def handle_event("toggle_mobile", _params, socket) do
    {:noreply, assign(socket, :mobile_open, !socket.assigns.mobile_open)}
  end

  @impl true
  def handle_event("open_mobile", _params, socket) do
    {:noreply, assign(socket, :mobile_open, true)}
  end

  @impl true
  def handle_event("close_mobile", _params, socket) do
    {:noreply, assign(socket, :mobile_open, false)}
  end

  @impl true
  def handle_event("toggle_all_projects", _params, socket) do
    {:noreply, assign(socket, :expanded_all_projects, !socket.assigns.expanded_all_projects)}
  end

  @impl true
  def handle_event("toggle_projects", _params, socket) do
    {:noreply, assign(socket, :expanded_projects, !socket.assigns.expanded_projects)}
  end

  @impl true
  def handle_event("toggle_system", _params, socket) do
    {:noreply, assign(socket, :expanded_system, !socket.assigns.expanded_system)}
  end

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    {:noreply, assign(socket, :expanded_chat, !socket.assigns.expanded_chat)}
  end

  @impl true
  def handle_event("show_new_channel", _params, socket) do
    {:noreply, assign(socket, :new_channel_name, "")}
  end

  @impl true
  def handle_event("cancel_new_channel", _params, socket) do
    {:noreply, assign(socket, :new_channel_name, nil)}
  end

  @impl true
  def handle_event("update_channel_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_channel_name, value)}
  end

  @impl true
  def handle_event("create_channel", _params, socket) do
    name = (socket.assigns.new_channel_name || "") |> String.trim()

    if name != "" do
      project_id = get_in(socket.assigns, [:sidebar_project, Access.key(:id)]) || 1
      channel_id = Channel.generate_id(project_id, name)

      case Channels.create_channel(%{
             id: channel_id,
             uuid: Ecto.UUID.generate(),
             name: name,
             channel_type: "public",
             project_id: project_id
           }) do
        {:ok, _channel} ->
          channels =
            case Channels.list_channels() do
              channels when is_list(channels) -> channels
              _ -> []
            end

          {:noreply,
           socket
           |> assign(:channels, channels)
           |> assign(:new_channel_name, nil)}

        {:error, _} ->
          {:noreply, assign(socket, :new_channel_name, nil)}
      end
    else
      {:noreply, assign(socket, :new_channel_name, nil)}
    end
  end

  @impl true
  def handle_event("new_session", %{"project_id" => project_id_str}, socket) do
    with {project_id, ""} <- Integer.parse(project_id_str),
         project <- Projects.get_project!(project_id),
         {:ok, %{session: session}} <-
           AgentManager.create_agent(
             project_id: project.id,
             project_path: project.path,
             model: "sonnet",
             eits_workflow: "0"
           ) do
      {:noreply, push_navigate(socket, to: "/dm/#{session.id}")}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_rename_project", %{"project_id" => id_str}, socket) do
    {id, ""} = Integer.parse(id_str)
    project = Projects.get_project!(id)
    {:noreply, assign(socket, renaming_project_id: id, rename_value: project.name)}
  end

  @impl true
  def handle_event("cancel_rename_project", _params, socket) do
    {:noreply, assign(socket, renaming_project_id: nil, rename_value: "")}
  end

  @impl true
  def handle_event("update_rename_value", %{"value" => value}, socket) do
    {:noreply, assign(socket, :rename_value, value)}
  end

  @impl true
  def handle_event("commit_rename_project", _params, socket) do
    name = String.trim(socket.assigns.rename_value)

    if name != "" && socket.assigns.renaming_project_id do
      project = Projects.get_project!(socket.assigns.renaming_project_id)
      Projects.update_project(project, %{name: name})
    end

    {:noreply,
     socket
     |> assign(:projects, Projects.list_projects())
     |> assign(:renaming_project_id, nil)
     |> assign(:rename_value, "")}
  end

  @impl true
  def handle_event("delete_project", %{"project_id" => id_str}, socket) do
    {id, ""} = Integer.parse(id_str)
    project = Projects.get_project!(id)
    Projects.delete_project(project)
    {:noreply, assign(socket, :projects, Projects.list_projects())}
  end

  @impl true
  def handle_event("show_new_project", _params, socket) do
    {:noreply,
     start_async(socket, :pick_folder, fn ->
       System.cmd(
         "osascript",
         ["-e", ~s[POSIX path of (choose folder with prompt "Select project folder:")]],
         stderr_to_stdout: true
       )
     end)}
  end

  @impl true
  def handle_event("cancel_new_project", _params, socket) do
    {:noreply, assign(socket, :new_project_path, nil)}
  end

  @impl true
  def handle_event("update_project_path", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_project_path, value)}
  end

  @impl true
  def handle_event("create_project", _params, socket) do
    path = (socket.assigns.new_project_path || "") |> String.trim()

    if path != "" do
      name = path |> String.split("/") |> Enum.reject(&(&1 == "")) |> List.last() || path

      case Projects.create_project(%{name: name, path: path}) do
        {:ok, _project} ->
          {:noreply,
           socket
           |> assign(:projects, Projects.list_projects())
           |> assign(:new_project_path, nil)}

        {:error, _} ->
          {:noreply, assign(socket, :new_project_path, nil)}
      end
    else
      {:noreply, assign(socket, :new_project_path, nil)}
    end
  end

  @impl true
  def handle_async(:pick_folder, {:ok, {path, 0}}, socket) do
    path = String.trim(path)
    name = path |> String.split("/") |> Enum.reject(&(&1 == "")) |> List.last() || path

    case Projects.create_project(%{name: name, path: path}) do
      {:ok, _project} ->
        {:noreply, assign(socket, :projects, Projects.list_projects())}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_async(:pick_folder, _result, socket) do
    # User cancelled or osascript failed — fall back to text input
    {:noreply, assign(socket, :new_project_path, "")}
  end

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
        data-active-project-id={@sidebar_project && @sidebar_project.id}
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
            <img src="/images/logo.svg" class="w-7 h-7 flex-shrink-0" />
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
      class={[
        "flex items-center gap-2.5 w-full text-left text-sm transition-colors",
        if(@collapsed, do: "px-4 py-1 justify-center", else: "px-3 py-1"),
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
      <span class={["truncate font-medium", if(@collapsed, do: "hidden")]}>Overview</span>
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

  attr :sidebar_tab, :atom, required: true
  attr :sidebar_project, :any, default: nil
  attr :collapsed, :boolean, required: true
  attr :expanded_system, :boolean, required: true
  attr :myself, :any, required: true

  defp system_section(assigns) do
    ~H"""
    <% system_active = @sidebar_tab in [:config, :jobs, :settings] && is_nil(@sidebar_project) %>
    <button
      phx-click="toggle_system"
      phx-target={@myself}
      class={[
        "flex items-center gap-2.5 w-full text-left text-sm transition-colors",
        if(@collapsed, do: "px-4 py-1 justify-center", else: "px-3 py-1"),
        if(system_active,
          do: "text-base-content/80 hover:bg-base-content/5",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5"
        )
      ]}
      title="System"
    >
      <%= if !@collapsed do %>
        <.icon
          name={if @expanded_system, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="w-3.5 h-3.5 flex-shrink-0"
        />
      <% end %>
      <.icon name="hero-squares-2x2" class="w-4 h-4 flex-shrink-0" />
      <span class={["truncate font-medium", if(@collapsed, do: "hidden")]}>System</span>
      <%= if system_active && !@collapsed do %>
        <span class="ml-auto w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
      <% end %>
    </button>

    <%= if @expanded_system || @collapsed do %>
      <div class={if !@collapsed, do: "ml-5 border-l border-base-content/8"}>
        <.section_sub_item
          href="/config"
          icon="hero-cog-6-tooth"
          label="Claude Config"
          active={@sidebar_tab == :config && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/jobs"
          icon="hero-calendar-days"
          label="Jobs"
          active={@sidebar_tab == :jobs}
          collapsed={@collapsed}
        />
        <.section_sub_item
          href="/settings"
          icon="hero-cog-8-tooth"
          label="Settings"
          active={@sidebar_tab == :settings}
          collapsed={@collapsed}
        />
      </div>
    <% end %>
    """
  end

  attr :sidebar_tab, :atom, required: true
  attr :collapsed, :boolean, required: true
  attr :expanded_chat, :boolean, required: true
  attr :channels, :list, required: true
  attr :active_channel_id, :any, default: nil
  attr :new_channel_name, :any, default: nil
  attr :myself, :any, required: true

  defp chat_section(assigns) do
    ~H"""
    <button
      phx-click="toggle_chat"
      phx-target={@myself}
      class={[
        "flex items-center gap-2.5 w-full text-left text-sm transition-colors",
        if(@collapsed, do: "px-4 py-1 justify-center", else: "px-3 py-1"),
        if(@sidebar_tab == :chat,
          do: "text-base-content/80 hover:bg-base-content/5",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5"
        )
      ]}
      title="Chat"
    >
      <%= if !@collapsed do %>
        <.icon
          name={if @expanded_chat, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
          class="w-3.5 h-3.5 flex-shrink-0"
        />
      <% end %>
      <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4 flex-shrink-0" />
      <span class={["truncate font-medium", if(@collapsed, do: "hidden")]}>Chat</span>
      <%= if @sidebar_tab == :chat && !@collapsed do %>
        <span class="ml-auto w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
      <% end %>
    </button>

    <%= if @expanded_chat && !@collapsed do %>
      <div class="ml-5 border-l border-base-content/8">
        <%= for channel <- @channels do %>
          <.link
            navigate={~p"/chat?channel_id=#{channel.id}"}
            class={[
              "block pl-3 pr-3 py-0.5 text-sm transition-colors",
              if(@active_channel_id && to_string(@active_channel_id) == to_string(channel.id),
                do: "text-primary font-medium bg-primary/5",
                else: "text-base-content/50 hover:text-base-content/75 hover:bg-base-content/5"
              )
            ]}
          >
            <span class="text-base-content/30 mr-0.5">#</span>{channel.name}
          </.link>
        <% end %>

        <%!-- New channel inline form or button --%>
        <%= if @new_channel_name do %>
          <form
            phx-submit="create_channel"
            phx-target={@myself}
            class="flex items-center gap-1 pl-3 pr-2 py-1"
          >
            <input
              type="text"
              name="name"
              value={@new_channel_name}
              phx-keyup="update_channel_name"
              phx-target={@myself}
              placeholder="channel-name"
              class="flex-1 bg-transparent border-b border-base-content/15 text-xs text-base-content/70 placeholder:text-base-content/25 outline-none py-0.5 font-mono"
              autofocus
            />
          </form>
        <% else %>
          <button
            phx-click="show_new_channel"
            phx-target={@myself}
            class="block pl-3 pr-3 py-0.5 text-sm text-base-content/30 hover:text-base-content/55 transition-colors w-full text-left"
          >
            + New Channel
          </button>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :projects, :list, required: true
  attr :sidebar_project, :any, default: nil
  attr :sidebar_tab, :atom, required: true
  attr :collapsed, :boolean, required: true
  attr :expanded_projects, :boolean, required: true
  attr :new_project_path, :any, default: nil
  attr :renaming_project_id, :any, default: nil
  attr :rename_value, :string, default: ""
  attr :myself, :any, required: true

  defp projects_section(assigns) do
    ~H"""
    <div class={["flex items-center", if(@collapsed, do: "px-4 py-1 justify-center", else: "px-3 py-1")]}>
      <button
        phx-click="toggle_projects"
        phx-target={@myself}
        class="flex items-center gap-2.5 flex-1 text-left text-sm text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5 transition-colors"
        title="Projects"
      >
        <%= if !@collapsed do %>
          <.icon
            name={if @expanded_projects, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
            class="w-3.5 h-3.5 flex-shrink-0"
          />
        <% end %>
        <.icon name="hero-folder-open" class="w-4 h-4 flex-shrink-0" />
        <span class={["truncate font-medium", if(@collapsed, do: "hidden")]}>Projects</span>
        <%= if !is_nil(@sidebar_project) && !@collapsed do %>
          <span class="ml-auto w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
        <% end %>
      </button>
      <%= if !@collapsed && @expanded_projects do %>
        <button
          phx-click="show_new_project"
          phx-target={@myself}
          class="flex-shrink-0 text-base-content/30 hover:text-base-content/60 transition-colors"
          title="New Project"
        >
          <.icon name="hero-plus-mini" class="w-3.5 h-3.5" />
        </button>
      <% end %>
    </div>

    <%= if @expanded_projects || @collapsed do %>
      <%!-- Inline new project path form --%>
      <%= if @new_project_path != nil && !@collapsed do %>
        <form
          phx-submit="create_project"
          phx-target={@myself}
          class="flex items-center gap-1 px-3 py-1"
        >
          <input
            type="text"
            name="path"
            value={@new_project_path}
            phx-keyup="update_project_path"
            phx-target={@myself}
            placeholder="/path/to/project"
            class="flex-1 bg-transparent border-b border-base-content/15 text-xs text-base-content/70 placeholder:text-base-content/25 outline-none py-0.5 font-mono"
            autofocus
          />
          <button
            type="button"
            phx-click="cancel_new_project"
            phx-target={@myself}
            class="text-base-content/30 hover:text-base-content/60 transition-colors flex-shrink-0"
          >
            <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
          </button>
        </form>
      <% end %>

      <%= for project <- @projects do %>
      <% is_active_project = @sidebar_project && @sidebar_project.id == project.id %>
      <div data-project-id={project.id}>
        <%!-- Project row --%>
        <div class={[
          "group flex items-center transition-colors",
          if(is_active_project,
            do: "bg-primary/10 border-l-2 border-primary",
            else: "hover:bg-base-content/5"
          )
        ]}>
          <%= if !@collapsed do %>
            <button
              data-project-toggle={project.id}
              class="pl-3 pr-1 py-1 text-base-content/40 hover:text-base-content/70 flex-shrink-0"
              title="Expand"
            >
              <span data-project-chevron={project.id}>
                <.icon name="hero-chevron-right-mini" class="w-3.5 h-3.5" />
              </span>
            </button>
          <% end %>
          <%= if !@collapsed && @renaming_project_id == project.id do %>
            <%!-- Inline rename input --%>
            <form
              phx-submit="commit_rename_project"
              phx-target={@myself}
              class="flex-1 flex items-center gap-1 pr-1"
            >
              <input
                type="text"
                name="name"
                value={@rename_value}
                phx-keyup="update_rename_value"
                phx-target={@myself}
                class="flex-1 min-w-0 bg-transparent border-b border-primary/40 text-sm text-base-content/80 outline-none py-0.5"
                autofocus
              />
              <button
                type="button"
                phx-click="cancel_rename_project"
                phx-target={@myself}
                class="flex-shrink-0 text-base-content/30 hover:text-base-content/60"
              >
                <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" />
              </button>
            </form>
          <% else %>
            <.link
              navigate={~p"/projects/#{project.id}"}
              class={[
                "flex items-center gap-2 flex-1 min-w-0 text-sm py-1 transition-colors",
                if(@collapsed, do: "px-4 justify-center", else: ""),
                if(is_active_project,
                  do: "text-primary font-medium",
                  else: "text-base-content/60 hover:text-base-content/80"
                )
              ]}
              title={project.name}
            >
              <.icon name="hero-folder" class="w-4 h-4 flex-shrink-0" />
              <span class={["truncate", if(@collapsed, do: "hidden")]}>{project.name}</span>
            </.link>
            <%= if !@collapsed do %>
              <%!-- ... dropdown menu --%>
              <div class="opacity-0 group-hover:opacity-100 flex-shrink-0 relative dropdown dropdown-end transition-all">
                <button
                  tabindex="0"
                  class="px-1 py-1 text-base-content/35 hover:text-base-content/70 transition-colors"
                  title="More options"
                >
                  <.icon name="hero-ellipsis-horizontal-mini" class="w-3.5 h-3.5" />
                </button>
                <ul
                  tabindex="0"
                  class="dropdown-content z-50 menu menu-xs bg-base-200 border border-base-content/10 rounded-lg shadow-lg w-44 p-1"
                >
                  <li>
                    <button
                      phx-click="start_rename_project"
                      phx-value-project_id={project.id}
                      phx-target={@myself}
                      class="flex items-center gap-2 text-sm"
                    >
                      <.icon name="hero-pencil-mini" class="w-3.5 h-3.5" /> Edit name
                    </button>
                  </li>
                  <li>
                    <button
                      phx-click="delete_project"
                      phx-value-project_id={project.id}
                      phx-target={@myself}
                      data-confirm={"Remove "#{project.name}"?"}
                      class="flex items-center gap-2 text-sm text-error hover:text-error"
                    >
                      <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" /> Remove
                    </button>
                  </li>
                </ul>
              </div>
              <%!-- New session (compose) button --%>
              <button
                phx-click="new_session"
                phx-value-project_id={project.id}
                phx-target={@myself}
                class="opacity-0 group-hover:opacity-100 flex-shrink-0 px-1 py-1 text-base-content/35 hover:text-primary transition-all"
                title="New session"
              >
                <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
              </button>
            <% end %>
          <% end %>
        </div>

        <%!-- Sub-items — always rendered, shown/hidden by JS --%>
        <div
          id={"project-sub-#{project.id}"}
          class={["ml-5 border-l border-base-content/8", if(@collapsed, do: "hidden")]}
          style="display: none;"
        >
          <.project_sub_item
            href={~p"/projects/#{project.id}/sessions"}
            label="Sessions"
            active={is_active_project && @sidebar_tab == :sessions}
          />
          <.project_sub_item
            href={~p"/projects/#{project.id}/kanban"}
            label="Tasks"
            active={is_active_project && (@sidebar_tab == :tasks || @sidebar_tab == :kanban)}
          />
          <.project_sub_item
            href={~p"/projects/#{project.id}/notes"}
            label="Notes"
            active={is_active_project && @sidebar_tab == :notes}
          />
          <.project_sub_item
            href={~p"/projects/#{project.id}/prompts"}
            label="Prompts"
            active={is_active_project && @sidebar_tab == :prompts}
          />
          <.project_sub_item
            href={~p"/projects/#{project.id}/files"}
            label="Files"
            active={is_active_project && @sidebar_tab == :files}
          />
          <.project_sub_item
            href={~p"/projects/#{project.id}/agents"}
            label="Agents"
            active={is_active_project && @sidebar_tab == :agents}
          />
          <.project_sub_item
            href={~p"/projects/#{project.id}/jobs"}
            label="Jobs"
            active={is_active_project && @sidebar_tab == :jobs}
          />
        </div>
      </div>
    <% end %>
    <% end %>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :collapsed, :boolean, default: false

  defp section_sub_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-2 text-sm transition-colors",
        if(@collapsed, do: "px-4 py-1 justify-center", else: "pl-3 pr-3 py-0.5"),
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
        "flex items-center gap-2 text-sm transition-colors",
        if(@collapsed, do: "px-4 py-1 justify-center", else: "pl-3 pr-3 py-0.5"),
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

  attr :href, :string, required: true
  attr :active, :boolean, default: false
  attr :collapsed, :boolean, default: false
  attr :count, :integer, default: 0

  defp notification_nav_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-2.5 text-base transition-colors",
        if(@collapsed, do: "px-4 py-1 justify-center", else: "px-3 py-1"),
        if(@active,
          do: "text-primary bg-primary/10 border-l-2 border-primary font-medium",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5"
        )
      ]}
      title="Notifications"
    >
      <div class="relative">
        <.icon name="hero-bell" class="w-4 h-4 flex-shrink-0" />
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

  attr :collapsed, :boolean, required: true
  attr :label, :string, required: true

  defp section_label(assigns) do
    ~H"""
    <div class={["mt-3 mb-0.5", if(@collapsed, do: "px-2", else: "px-3")]}>
      <span class={[
        "text-[10px] uppercase tracking-wider font-medium text-base-content/30",
        if(@collapsed, do: "hidden")
      ]}>
        {@label}
      </span>
      <div class={["border-t border-base-content/8 mt-1", if(!@collapsed, do: "hidden")]} />
    </div>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :collapsed, :boolean, default: false

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-2.5 text-base transition-colors",
        if(@collapsed, do: "px-4 py-1 justify-center", else: "px-3 py-1"),
        if(@active,
          do: "text-primary bg-primary/10 border-l-2 border-primary font-medium",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5"
        )
      ]}
      title={@label}
    >
      <.icon name={@icon} class="w-4 h-4 flex-shrink-0" />
      <span class={["truncate", if(@collapsed, do: "hidden")]}>{@label}</span>
    </.link>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp project_sub_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "block pl-4 pr-3 py-0.5 text-sm transition-colors",
        if(@active,
          do: "text-primary font-medium bg-primary/5",
          else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/5"
        )
      ]}
    >
      {@label}
    </.link>
    """
  end

  defp theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5 rounded-full bg-base-content/5 p-0.5">
      <button
        class="p-1 rounded-full hover:bg-base-content/10 transition-colors"
        phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        title="System theme"
      >
        <.icon name="hero-computer-desktop-micro" class="w-3.5 h-3.5 text-base-content/40" />
      </button>
      <button
        class="p-1 rounded-full hover:bg-base-content/10 transition-colors"
        phx-click={Phoenix.LiveView.JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light theme"
      >
        <.icon name="hero-sun-micro" class="w-3.5 h-3.5 text-base-content/40" />
      </button>
      <button
        class="p-1 rounded-full hover:bg-base-content/10 transition-colors"
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
