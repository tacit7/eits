defmodule EyeInTheSkyWebWeb.Components.Sidebar.ProjectsSection do
  use EyeInTheSkyWebWeb, :html

  attr :projects, :list, required: true
  attr :sidebar_project, :any, default: nil
  attr :sidebar_tab, :atom, required: true
  attr :collapsed, :boolean, required: true
  attr :expanded_projects, :boolean, required: true
  attr :new_project_path, :any, default: nil
  attr :renaming_project_id, :any, default: nil
  attr :rename_value, :string, default: ""
  attr :myself, :any, required: true

  def projects_section(assigns) do
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
                      data-confirm={"Remove \"#{project.name}\"?"}
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
end
