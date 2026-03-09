defmodule EyeInTheSkyWebWeb.Components.Sidebar do
  use EyeInTheSkyWebWeb, :live_component

  alias EyeInTheSkyWeb.{Projects, Channels}
  alias EyeInTheSkyWeb.Channels.Channel

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
       expanded_chat: false,
       new_channel_name: nil
     )}
  end

  @impl true
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
     |> assign(:expanded_chat, expanded_chat)}
  end

  @impl true
  def handle_event("toggle_collapsed", _params, socket) do
    {:noreply, assign(socket, :collapsed, !socket.assigns.collapsed)}
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
  def handle_event("pick_project_folder", _params, socket) do
    case System.cmd("osascript", ["-e", "POSIX path of (choose folder)"]) do
      {path, 0} ->
        path = String.trim(path)
        name = path |> String.split("/") |> Enum.reject(&(&1 == "")) |> List.last() || path

        case Projects.create_project(%{name: name, path: path}) do
          {:ok, _project} ->
            {:noreply, assign(socket, :projects, Projects.list_projects())}

          {:error, _} ->
            {:noreply, socket}
        end

      {_err, _code} ->
        # User cancelled the dialog
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <aside
      id="app-sidebar"
      phx-hook="SidebarState"
      phx-target={@myself}
      data-active-project-id={@sidebar_project && @sidebar_project.id}
      class={[
        "flex flex-col h-full border-r border-base-content/8 bg-[oklch(95%_0.005_80)] dark:bg-[hsl(30,3.3%,11.8%)] transition-all duration-200 flex-shrink-0 overflow-hidden",
        if(@collapsed, do: "w-16", else: "w-60")
      ]}
    >
      <%!-- Branding --%>
      <div class="flex items-center gap-2 px-3 py-3 border-b border-base-content/5">
        <.link navigate="/" class="flex items-center gap-2 min-w-0">
          <img src="/images/logo.svg" class="w-7 h-7 flex-shrink-0" />
          <span class={[
            "text-sm font-semibold text-base-content/80 truncate",
            if(@collapsed, do: "hidden")
          ]}>
            Eye in the Sky
          </span>
        </.link>
      </div>

      <%!-- Scrollable nav --%>
      <nav class="flex-1 overflow-y-auto overflow-x-hidden py-2">
        <.nav_item
          href="/"
          icon="hero-cpu-chip"
          label="Sessions"
          active={@sidebar_tab == :sessions && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.nav_item
          href="/tasks"
          icon="hero-clipboard-document-list"
          label="Tasks"
          active={@sidebar_tab == :tasks && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.nav_item
          href="/notes"
          icon="hero-document-text"
          label="Notes"
          active={@sidebar_tab == :notes && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.nav_item
          href="/usage"
          icon="hero-chart-bar"
          label="Usage"
          active={@sidebar_tab == :usage}
          collapsed={@collapsed}
        />
        <.nav_item
          href="/prompts"
          icon="hero-chat-bubble-left-right"
          label="Prompts"
          active={@sidebar_tab == :prompts && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.nav_item
          href="/skills"
          icon="hero-bolt"
          label="Skills"
          active={@sidebar_tab == :skills}
          collapsed={@collapsed}
        />
        <%!-- Chat (expandable with channels) --%>
        <div>
          <button
            phx-click="toggle_chat"
            phx-target={@myself}
            class={[
              "flex items-center gap-2.5 w-full text-left text-[13px] transition-colors",
              if(@collapsed, do: "px-4 py-1 justify-center", else: "px-3 py-1"),
              if(@sidebar_tab == :chat,
                do: "text-primary bg-primary/10 border-l-2 border-primary font-medium",
                else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5"
              )
            ]}
            title="Chat"
          >
            <%= if !@collapsed do %>
              <.icon
                name={
                  if @expanded_chat, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"
                }
                class="w-3.5 h-3.5 flex-shrink-0"
              />
            <% end %>
            <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4 flex-shrink-0" />
            <span class={["truncate", if(@collapsed, do: "hidden")]}>Chat</span>
          </button>

          <%= if @expanded_chat && !@collapsed do %>
            <div class="ml-5 border-l border-base-content/8">
              <%= for channel <- @channels do %>
                <.link
                  navigate={~p"/chat?channel_id=#{channel.id}"}
                  class={[
                    "block pl-4 pr-3 py-1 text-xs transition-colors",
                    if(@active_channel_id && to_string(@active_channel_id) == to_string(channel.id),
                      do: "text-primary font-medium bg-primary/5",
                      else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/5"
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
                  class="flex items-center gap-1 pl-4 pr-2 py-1"
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
                  class="block pl-4 pr-3 py-1 text-xs text-base-content/30 hover:text-base-content/55 transition-colors w-full text-left"
                >
                  + New Channel
                </button>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Projects section --%>
        <div class={["mt-3 mb-0.5 flex items-center justify-between", if(@collapsed, do: "px-2", else: "px-3")]}>
          <span class={[
            "text-[10px] uppercase tracking-wider font-medium text-base-content/30",
            if(@collapsed, do: "hidden")
          ]}>
            Projects
          </span>
          <div class={["border-t border-base-content/8 mt-1 flex-1", if(!@collapsed, do: "hidden")]} />
          <%= if !@collapsed do %>
            <button
              phx-click="pick_project_folder"
              phx-target={@myself}
              class="text-base-content/30 hover:text-base-content/60 transition-colors"
              title="New Project"
            >
              <.icon name="hero-plus-mini" class="w-3.5 h-3.5" />
            </button>
          <% end %>
        </div>
        <%= for project <- @projects do %>
          <% is_active_project = @sidebar_project && @sidebar_project.id == project.id %>
          <div data-project-id={project.id}>
            <%!-- Project row --%>
            <div class={[
              "flex items-center transition-colors",
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
              <.link
                navigate={~p"/projects/#{project.id}"}
                class={[
                  "flex items-center gap-2 flex-1 min-w-0 text-sm py-1 transition-colors",
                  if(@collapsed, do: "px-4 justify-center", else: "pr-3"),
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
                href={~p"/projects/#{project.id}/tasks"}
                label="Tasks"
                active={is_active_project && @sidebar_tab == :tasks}
              />
              <.project_sub_item
                href={~p"/projects/#{project.id}/kanban"}
                label="Kanban"
                active={is_active_project && @sidebar_tab == :kanban}
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
                href={~p"/projects/#{project.id}/config"}
                label="Config"
                active={is_active_project && @sidebar_tab == :config}
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

        <%!-- System section --%>
        <.section_label collapsed={@collapsed} label="System" />
        <.nav_item
          href="/config"
          icon="hero-cog-6-tooth"
          label="Claude Config"
          active={@sidebar_tab == :config && is_nil(@sidebar_project)}
          collapsed={@collapsed}
        />
        <.nav_item
          href="/jobs"
          icon="hero-calendar-days"
          label="Jobs"
          active={@sidebar_tab == :jobs}
          collapsed={@collapsed}
        />
        <.nav_item
          href="/oban"
          icon="hero-queue-list"
          label="Oban"
          active={false}
          collapsed={@collapsed}
        />
        <.nav_item
          href="/settings"
          icon="hero-cog-8-tooth"
          label="Settings"
          active={@sidebar_tab == :settings}
          collapsed={@collapsed}
        />
      </nav>

      <%!-- Bottom controls --%>
      <div class="border-t border-base-content/5 p-2 flex items-center gap-2">
        <%= if !@collapsed do %>
          <div class="flex-1">
            <.theme_toggle />
          </div>
        <% end %>
        <button
          phx-click="toggle_collapsed"
          phx-target={@myself}
          class="btn btn-ghost btn-xs btn-square text-base-content/40 hover:text-base-content/70"
          title={if @collapsed, do: "Expand sidebar", else: "Collapse sidebar"}
        >
          <.icon
            name={
              if @collapsed,
                do: "hero-chevron-double-right-mini",
                else: "hero-chevron-double-left-mini"
            }
            class="w-4 h-4"
          />
        </button>
      </div>
    </aside>
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
        "flex items-center gap-2.5 text-[13px] transition-colors",
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
        "block pl-4 pr-3 py-0.5 text-xs transition-colors",
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
