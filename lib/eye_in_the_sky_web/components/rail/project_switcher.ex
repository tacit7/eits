defmodule EyeInTheSkyWeb.Components.Rail.ProjectSwitcher do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.Rail.Helpers, only: [project_initial: 1]

  attr :projects, :list, required: true
  attr :sidebar_project, :any, default: nil
  attr :open, :boolean, default: false
  attr :new_project_path, :any, default: nil
  attr :workspace, :any, default: nil
  attr :scope_type, :atom, default: :project

  def project_switcher(assigns) do
    ~H"""
    <div
      :if={@open}
      id="project-switcher"
      class="absolute left-[52px] top-[48px] z-50 w-[236px] overflow-hidden rounded-box border border-base-content/10 bg-[var(--surface-flyout)] shadow-lg text-base-content"
    >
      <div class="border-b border-base-content/8 px-3 py-2.5 text-micro font-semibold uppercase tracking-normal text-base-content/40">
        Switch Context
      </div>

      <%!-- WORKSPACE section --%>
      <div class="px-3 pt-2 pb-1 text-nano font-semibold uppercase tracking-normal text-base-content/30">
        Workspace
      </div>
      <div class="px-1.5 pb-1.5">
        <% ws_selected = @scope_type == :workspace %>
        <button
          id="project-switcher-workspace"
          type="button"
          phx-click="select_workspace"
          class={[
            "focus-ring flex h-8 w-full items-center gap-2 rounded-box px-2 text-left text-message transition-colors",
            if(ws_selected,
              do: "bg-primary/10 text-primary",
              else: "text-base-content/70 hover:bg-base-content/5 hover:text-base-content/90"
            )
          ]}
        >
          <div class={[
            "flex size-6 flex-shrink-0 items-center justify-center rounded-box text-nano font-bold",
            if(ws_selected,
              do: "bg-primary text-primary-content",
              else: "bg-base-content/10 text-base-content/60"
            )
          ]}>
            <.icon name="hero-squares-2x2-mini" class="size-3.5" />
          </div>
          <div class="flex-1 min-w-0">
            <div class="font-medium truncate">
              {if @workspace, do: @workspace.name, else: "Personal Workspace"}
            </div>
          </div>
          <.icon :if={ws_selected} name="hero-check-mini" class="size-3.5 flex-shrink-0" />
        </button>
      </div>

      <%!-- PROJECTS section --%>
      <div class="border-t border-base-content/8 px-3 pt-2 pb-1 text-nano font-semibold uppercase tracking-normal text-base-content/30">
        Projects
      </div>
      <div id="project-switcher-projects" class="max-h-52 overflow-y-auto p-1.5 text-base-content">
        <%= if @projects == [] do %>
          <div class="rounded-box px-2 py-2 text-message text-base-content/35">No projects</div>
        <% else %>
          <%= for project <- @projects do %>
            <% selected =
              @scope_type == :project && not is_nil(@sidebar_project) &&
                @sidebar_project.id == project.id %>
            <div
              class="group/proj relative flex items-center"
              data-ctx="project"
              data-ctx-id={project.id}
              data-ctx-name={project.name}
              data-ctx-path={project.path}
            >
              <button
                id={"project-switcher-project-#{project.id}"}
                type="button"
                phx-click="select_project"
                phx-value-project_id={project.id}
                class={[
                  "focus-ring flex h-8 flex-1 items-center gap-2 rounded-box px-2 text-left text-message transition-colors",
                  if(selected,
                    do: "bg-primary/10 text-primary",
                    else: "text-base-content/70 hover:bg-base-content/5 hover:text-base-content/90"
                  )
                ]}
              >
                <div class={[
                  "flex size-6 flex-shrink-0 items-center justify-center rounded-box text-nano font-bold",
                  if(selected,
                    do: "bg-primary text-primary-content",
                    else: "bg-base-content/10 text-base-content/60"
                  )
                ]}>
                  {project_initial(project)}
                </div>
                <div class="flex-1 min-w-0">
                  <div class="font-medium truncate">{project.name}</div>
                </div>
                <.icon :if={selected} name="hero-check-mini" class="size-3.5 flex-shrink-0" />
              </button>
              <%!-- Open in New Window is only meaningful in Tauri; shown on hover. --%>
              <button
                type="button"
                phx-click="open_in_window"
                phx-value-project_id={project.id}
                title="Open in New Window"
                aria-label={"Open #{project.name} in new window"}
                class="focus-ring absolute right-1 flex size-6 items-center justify-center rounded-box text-base-content/35 opacity-0 transition-[color,background-color,opacity] hover:bg-base-content/8 hover:text-base-content/75 group-hover/proj:opacity-100"
              >
                <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
              </button>
            </div>
          <% end %>
        <% end %>
      </div>

      <div class="border-t border-base-content/8 p-1.5">
        <%= if is_nil(@new_project_path) do %>
          <button
            id="project-switcher-show-new"
            type="button"
            phx-click="show_new_project"
            class="focus-ring flex h-8 w-full items-center gap-2 rounded-box px-2 text-message text-base-content/50 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
          >
            <.icon name="hero-plus-mini" class="size-3.5" /> Add repo
          </button>
        <% else %>
          <form
            id="project-switcher-new-project-form"
            phx-submit="create_project"
            class="flex items-center gap-1 px-2 py-1.5"
          >
            <input
              id="project-switcher-new-project-path"
              type="text"
              name="path"
              value={@new_project_path}
              phx-keyup="update_project_path"
              placeholder="/path/to/project"
              class="focus-ring min-w-0 flex-1 border-b border-primary/40 bg-transparent py-0.5 font-mono text-mini text-base-content/80 outline-none placeholder:text-base-content/25 focus:border-primary"
              autofocus
            />
            <button
              type="submit"
              class="focus-ring flex size-6 items-center justify-center rounded-box text-primary hover:bg-base-content/8 hover:text-primary/80"
              aria-label="Create project"
            >
              <.icon name="hero-check-mini" class="size-3.5" />
            </button>
            <button
              type="button"
              phx-click="cancel_new_project"
              class="focus-ring flex size-6 items-center justify-center rounded-box text-base-content/30 hover:bg-base-content/8 hover:text-base-content/60"
              aria-label="Cancel"
            >
              <.icon name="hero-x-mark-mini" class="size-3.5" />
            </button>
          </form>
        <% end %>
      </div>
    </div>
    """
  end
end
