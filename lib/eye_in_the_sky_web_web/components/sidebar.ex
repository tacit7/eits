defmodule EyeInTheSkyWebWeb.Components.Sidebar do
  use EyeInTheSkyWebWeb, :live_component

  alias EyeInTheSkyWeb.Projects

  @impl true
  def mount(socket) do
    projects = Projects.list_projects()

    {:ok,
     assign(socket,
       projects: projects,
       collapsed: false,
       expanded_projects: MapSet.new()
     )}
  end

  @impl true
  def update(assigns, socket) do
    sidebar_project = assigns[:sidebar_project]

    # Auto-expand the active project
    expanded =
      if sidebar_project do
        MapSet.put(socket.assigns.expanded_projects, sidebar_project.id)
      else
        socket.assigns.expanded_projects
      end

    {:ok,
     socket
     |> assign(:sidebar_tab, assigns[:sidebar_tab] || :sessions)
     |> assign(:sidebar_project, sidebar_project)
     |> assign(:expanded_projects, expanded)}
  end

  @impl true
  def handle_event("toggle_collapsed", _params, socket) do
    {:noreply, assign(socket, :collapsed, !socket.assigns.collapsed)}
  end

  @impl true
  def handle_event("toggle_project", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    expanded = socket.assigns.expanded_projects

    expanded =
      if MapSet.member?(expanded, id) do
        MapSet.delete(expanded, id)
      else
        MapSet.put(expanded, id)
      end

    {:noreply, assign(socket, :expanded_projects, expanded)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <aside
      id="app-sidebar"
      phx-hook="SidebarState"
      phx-target={@myself}
      class={[
        "flex flex-col h-full border-r border-base-content/8 bg-[oklch(95%_0.005_80)] dark:bg-[oklch(12%_0.005_260)] transition-all duration-200 flex-shrink-0 overflow-hidden",
        if(@collapsed, do: "w-16", else: "w-60")
      ]}
    >
      <%!-- Branding --%>
      <div class="flex items-center gap-2 px-3 py-3 border-b border-base-content/5">
        <a href="/" class="flex items-center gap-2 min-w-0">
          <img src="/images/logo.svg" class="w-7 h-7 flex-shrink-0" />
          <span class={["text-sm font-semibold text-base-content/80 truncate", if(@collapsed, do: "hidden")]}>
            Eye in the Sky
          </span>
        </a>
      </div>

      <%!-- Scrollable nav --%>
      <nav class="flex-1 overflow-y-auto overflow-x-hidden py-2">
        <%!-- Overview section --%>
        <.section_label collapsed={@collapsed} label="Overview" />
        <.nav_item href="/" icon="hero-cpu-chip" label="Sessions" active={@sidebar_tab == :sessions && is_nil(@sidebar_project)} collapsed={@collapsed} />
        <.nav_item href="/notes" icon="hero-document-text" label="Notes" active={@sidebar_tab == :notes && is_nil(@sidebar_project)} collapsed={@collapsed} />
        <.nav_item href="/tasks" icon="hero-clipboard-document-list" label="Tasks" active={@sidebar_tab == :tasks && is_nil(@sidebar_project)} collapsed={@collapsed} />
        <.nav_item href="/usage" icon="hero-chart-bar" label="Usage" active={@sidebar_tab == :usage} collapsed={@collapsed} />
        <.nav_item href="/prompts" icon="hero-chat-bubble-left-right" label="Prompts" active={@sidebar_tab == :prompts && is_nil(@sidebar_project)} collapsed={@collapsed} />
        <.nav_item href="/skills" icon="hero-bolt" label="Skills" active={@sidebar_tab == :skills} collapsed={@collapsed} />
        <.nav_item href="/chat" icon="hero-chat-bubble-left-ellipsis" label="Chat" active={@sidebar_tab == :chat} collapsed={@collapsed} />

        <%!-- Projects section --%>
        <.section_label collapsed={@collapsed} label="Projects" />
        <%= for project <- @projects do %>
          <% is_active_project = @sidebar_project && @sidebar_project.id == project.id %>
          <% is_expanded = MapSet.member?(@expanded_projects, project.id) %>
          <div>
            <%!-- Project row --%>
            <button
              phx-click="toggle_project"
              phx-value-id={project.id}
              phx-target={@myself}
              class={[
                "flex items-center gap-2 w-full text-left text-sm transition-colors",
                if(@collapsed, do: "px-4 py-1.5 justify-center", else: "px-3 py-1.5"),
                if(is_active_project,
                  do: "text-primary bg-primary/10 border-l-2 border-primary",
                  else: "text-base-content/60 hover:text-base-content/80 hover:bg-base-content/5"
                )
              ]}
              title={project.name}
            >
              <%= if !@collapsed do %>
                <.icon
                  name={if is_expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
                  class="w-3.5 h-3.5 flex-shrink-0"
                />
              <% end %>
              <.icon name="hero-folder" class="w-4 h-4 flex-shrink-0" />
              <span class={["truncate", if(@collapsed, do: "hidden")]}>{project.name}</span>
            </button>

            <%!-- Sub-items (when expanded and not collapsed) --%>
            <%= if is_expanded && !@collapsed do %>
              <div class="ml-5 border-l border-base-content/8">
                <.project_sub_item
                  href={~p"/projects/#{project.id}"}
                  label="Overview"
                  active={is_active_project && @sidebar_tab == :overview}
                />
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
              </div>
            <% end %>
          </div>
        <% end %>

        <%!-- System section --%>
        <.section_label collapsed={@collapsed} label="System" />
        <.nav_item href="/config" icon="hero-cog-6-tooth" label="Claude Config" active={@sidebar_tab == :config && is_nil(@sidebar_project)} collapsed={@collapsed} />
        <.nav_item href="/jobs" icon="hero-calendar-days" label="Jobs" active={@sidebar_tab == :jobs} collapsed={@collapsed} />
        <.nav_item href="/settings" icon="hero-cog-8-tooth" label="Settings" active={@sidebar_tab == :settings} collapsed={@collapsed} />
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
            name={if @collapsed, do: "hero-chevron-double-right-mini", else: "hero-chevron-double-left-mini"}
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
    <div class={["mt-4 mb-1", if(@collapsed, do: "px-2", else: "px-3")]}>
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
    <a
      href={@href}
      class={[
        "flex items-center gap-2.5 text-[13px] transition-colors",
        if(@collapsed, do: "px-4 py-1.5 justify-center", else: "px-3 py-1.5"),
        if(@active,
          do: "text-primary bg-primary/10 border-l-2 border-primary font-medium",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5"
        )
      ]}
      title={@label}
    >
      <.icon name={@icon} class="w-4 h-4 flex-shrink-0" />
      <span class={["truncate", if(@collapsed, do: "hidden")]}>{@label}</span>
    </a>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp project_sub_item(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "block pl-4 pr-3 py-1 text-xs transition-colors",
        if(@active,
          do: "text-primary font-medium bg-primary/5",
          else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/5"
        )
      ]}
    >
      {@label}
    </a>
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
