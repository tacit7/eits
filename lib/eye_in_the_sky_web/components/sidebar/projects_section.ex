defmodule EyeInTheSkyWeb.Components.Sidebar.ProjectsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

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
        data-section-toggle="projects"
        class="flex items-center gap-2.5 flex-1 text-left text-sm text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5 transition-colors min-h-[44px]"
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
        <%= if not is_nil(@sidebar_project) && !@collapsed do %>
          <span class="ml-auto w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
        <% end %>
      </button>
      <%= if !@collapsed && @expanded_projects do %>
        <button
          phx-click="show_new_project"
          phx-target={@myself}
          class="flex-shrink-0 min-h-[44px] min-w-[44px] flex items-center justify-center text-base-content/30 hover:text-base-content/60 transition-colors"
          title="New Project"
        >
          <.icon name="hero-plus-mini" class="w-3.5 h-3.5" />
        </button>
      <% end %>
    </div>

    <%= if @expanded_projects || @collapsed do %>
      <%!-- Inline new project path form --%>
      <%= if not is_nil(@new_project_path) && !@collapsed do %>
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
            class="flex-1 bg-transparent border-b border-base-content/15 text-base text-base-content/70 placeholder:text-base-content/25 outline-none py-0.5 font-mono"
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
        <% is_selected = not is_nil(@sidebar_project) && @sidebar_project.id == project.id %>
        <div data-project-id={project.id}>
          <%!-- Project row --%>
          <div class={[
            "group flex items-center transition-colors",
            if(is_selected,
              do: "bg-primary/15 border-l-2 border-primary",
              else: "hover:bg-base-content/5"
            )
          ]}>
            <%= if !@collapsed && @renaming_project_id == project.id do %>
              <%!-- Inline rename input --%>
              <form
                phx-submit="commit_rename_project"
                phx-target={@myself}
                class="flex-1 flex items-center gap-1 pl-3 pr-1"
              >
                <input
                  type="text"
                  name="name"
                  value={@rename_value}
                  phx-keyup="update_rename_value"
                  phx-target={@myself}
                  class="flex-1 min-w-0 bg-transparent border-b border-primary/40 text-base text-base-content/80 outline-none py-0.5"
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
              <button
                phx-click="select_project"
                phx-value-project_id={project.id}
                phx-target={@myself}
                class={[
                  "flex items-center gap-2 flex-1 min-w-0 text-sm py-1 min-h-[44px] transition-colors text-left",
                  if(@collapsed, do: "px-4 justify-center", else: "pl-3"),
                  if(is_selected,
                    do: "text-primary font-semibold",
                    else: "text-base-content/60 hover:text-base-content/80"
                  )
                ]}
                title={project.name}
              >
                <.icon
                  name={if is_selected, do: "hero-folder-open", else: "hero-folder"}
                  class={if is_selected, do: "w-4 h-4 flex-shrink-0 text-primary", else: "w-4 h-4 flex-shrink-0"}
                />
                <span class={["truncate", if(@collapsed, do: "hidden")]}>{project.name}</span>
              </button>
              <%= if !@collapsed do %>
                <%!-- Hover action menu --%>
                <div class="opacity-0 group-hover:opacity-100 flex-shrink-0 relative dropdown dropdown-end transition-all">
                  <button
                    tabindex="0"
                    class="min-h-[44px] min-w-[44px] flex items-center justify-center text-base-content/35 hover:text-base-content/70 transition-colors"
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
                        phx-click="set_bookmark"
                        phx-value-id={project.id}
                        phx-value-bookmarked={"#{!project.bookmarked}"}
                        phx-target={@myself}
                        phx-disable-with=""
                        class="flex items-center gap-2 text-sm"
                      >
                        <.icon
                          name={if project.bookmarked, do: "hero-bookmark-solid", else: "hero-bookmark"}
                          class="w-3.5 h-3.5"
                        />
                        {if project.bookmarked, do: "Unbookmark", else: "Bookmark"}
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
                <%!-- New session button --%>
                <button
                  phx-click="new_session"
                  phx-value-project_id={project.id}
                  phx-target={@myself}
                  class="opacity-0 group-hover:opacity-100 flex-shrink-0 min-h-[44px] min-w-[44px] flex items-center justify-center text-base-content/35 hover:text-primary transition-all"
                  title="New session"
                >
                  <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
                </button>
              <% end %>
            <% end %>
          </div>

          <%!-- Docked project panel — server-side, renders only for selected project --%>
          <%= if is_selected && !@collapsed do %>
            <div class="mb-1 ml-3.5 border-t-2 border-primary border-r border-b border-primary/15 rounded-br-md bg-primary/[0.03]">
              <.panel_nav_item
                href={~p"/projects/#{@sidebar_project.id}"}
                icon="hero-home"
                label="Overview"
                active={@sidebar_tab == :overview}
              />
              <.panel_nav_item
                href={~p"/projects/#{@sidebar_project.id}/sessions"}
                icon="hero-cpu-chip"
                label="Sessions"
                active={@sidebar_tab == :sessions}
              />
              <.panel_nav_item
                href={~p"/projects/#{@sidebar_project.id}/kanban"}
                icon="hero-clipboard-document-list"
                label="Tasks"
                active={@sidebar_tab in [:tasks, :kanban]}
              />
              <.panel_nav_item
                href={~p"/projects/#{@sidebar_project.id}/prompts"}
                icon="hero-chat-bubble-left-right"
                label="Prompts"
                active={@sidebar_tab == :prompts}
              />
              <.panel_nav_item
                href={~p"/projects/#{@sidebar_project.id}/notes"}
                icon="hero-document-text"
                label="Notes"
                active={@sidebar_tab == :notes}
              />
              <.panel_nav_item
                href={~p"/projects/#{@sidebar_project.id}/files"}
                icon="hero-folder-open"
                label="Files"
                active={@sidebar_tab == :files}
              />
              <.panel_nav_item
                href={~p"/projects/#{@sidebar_project.id}/agents"}
                icon="hero-users"
                label="Agents"
                active={@sidebar_tab == :agents}
              />
              <.panel_nav_item
                href={~p"/projects/#{@sidebar_project.id}/jobs"}
                icon="hero-clock"
                label="Jobs"
                active={@sidebar_tab == :jobs}
              />
            </div>
          <% end %>
        </div>
      <% end %>
    <% end %>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp panel_nav_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-1.5 pl-2.5 pr-2 py-1 min-h-[44px] text-xs border-l-2 transition-colors",
        if(@active,
          do: "text-primary bg-primary/10 border-primary font-medium",
          else: "text-base-content/50 hover:text-base-content/75 hover:bg-primary/5 border-transparent"
        )
      ]}
    >
      <.icon name={@icon} class="w-3 h-3 flex-shrink-0" />
      <span class="truncate">{@label}</span>
    </.link>
    """
  end
end
