defmodule EyeInTheSkyWeb.Components.Rail.ProjectSwitcher do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.Rail.Helpers, only: [project_initial: 1]

  attr :projects, :list, required: true
  attr :sidebar_project, :any, default: nil
  attr :open, :boolean, default: false
  attr :new_project_path, :any, default: nil
  attr :myself, :any, required: true
  attr :workspace, :any, default: nil
  attr :scope_type, :atom, default: :project

  def project_switcher(assigns) do
    ~H"""
    <div
      :if={@open}
      class="absolute left-[52px] top-[48px] z-50 w-64 bg-base-200 border border-base-content/10 rounded-xl shadow-2xl overflow-hidden"
    >
      <div class="px-3 py-2.5 border-b border-base-content/8 text-micro font-semibold uppercase tracking-widest text-base-content/40">
        Switch Context
      </div>

      <%!-- WORKSPACE section --%>
      <div class="px-3 pt-2 pb-0.5 text-nano font-semibold uppercase tracking-widest text-base-content/30">
        Workspace
      </div>
      <div class="px-1.5 pb-1.5">
        <% ws_selected = @scope_type == :workspace %>
        <button
          phx-click="select_workspace"
          phx-target={@myself}
          class={[
            "w-full flex items-center gap-2.5 px-2 py-2 rounded-lg text-sm text-left transition-colors",
            if(ws_selected,
              do: "bg-primary/10 text-primary",
              else: "text-base-content/70 hover:bg-base-content/5 hover:text-base-content/90"
            )
          ]}
        >
          <div class={[
            "w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0 text-xs font-bold",
            if(ws_selected, do: "bg-primary text-white", else: "bg-base-content/10 text-base-content/60")
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
      <div class="px-3 pt-1 pb-0.5 text-nano font-semibold uppercase tracking-widest text-base-content/30 border-t border-base-content/8">
        Projects
      </div>
      <div class="p-1.5 max-h-48 overflow-y-auto">
        <%= for project <- @projects do %>
          <% selected = @scope_type == :project && not is_nil(@sidebar_project) && @sidebar_project.id == project.id %>
          <button
            phx-click="select_project"
            phx-value-project_id={project.id}
            phx-target={@myself}
            class={[
              "w-full flex items-center gap-2.5 px-2 py-2 rounded-lg text-sm text-left transition-colors",
              if(selected,
                do: "bg-primary/10 text-primary",
                else: "text-base-content/70 hover:bg-base-content/5 hover:text-base-content/90"
              )
            ]}
          >
            <div class={[
              "w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0 text-xs font-bold",
              if(selected, do: "bg-primary text-white", else: "bg-base-content/10 text-base-content/60")
            ]}>
              {project_initial(project)}
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate">{project.name}</div>
            </div>
            <.icon :if={selected} name="hero-check-mini" class="size-3.5 flex-shrink-0" />
          </button>
        <% end %>
      </div>

      <div class="border-t border-base-content/8 p-1.5">
        <%= if is_nil(@new_project_path) do %>
          <button
            phx-click="show_new_project"
            phx-target={@myself}
            class="w-full flex items-center gap-2 px-2 py-2 rounded-lg text-sm text-base-content/50 hover:text-base-content/80 hover:bg-base-content/5 transition-colors"
          >
            <.icon name="hero-plus-mini" class="size-3.5" />
            New project
          </button>
        <% else %>
          <form phx-submit="create_project" phx-target={@myself} class="flex items-center gap-1 px-2 py-1">
            <input
              type="text"
              name="path"
              value={@new_project_path}
              phx-keyup="update_project_path"
              phx-target={@myself}
              placeholder="/path/to/project"
              class="flex-1 bg-transparent border-b border-primary/40 text-sm text-base-content/80 placeholder:text-base-content/25 outline-none py-0.5 font-mono"
              autofocus
            />
            <button
              type="submit"
              class="text-primary hover:text-primary/80"
              aria-label="Create project"
            >
              <.icon name="hero-check-mini" class="size-3.5" />
            </button>
            <button
              type="button"
              phx-click="cancel_new_project"
              phx-target={@myself}
              class="text-base-content/30 hover:text-base-content/60"
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
