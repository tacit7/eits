defmodule EyeInTheSkyWebWeb.Components.ProjectNav do
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWebWeb.Endpoint,
    router: EyeInTheSkyWebWeb.Router

  attr :project, :map, required: true
  attr :tasks, :list, default: []
  attr :current_tab, :atom, required: true

  def render(assigns) do
    ~H"""
    <!-- GitHub-style Project Navigation -->
    <div class="border-b border-base-300 bg-base-100">
      <div class="px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between py-3">
          <!-- Project Name -->
          <div class="flex items-center gap-2">
            <svg class="w-5 h-5 text-base-content/60" fill="currentColor" viewBox="0 0 16 16">
              <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z" />
            </svg>
            <h1 class="text-xl font-semibold text-base-content">{@project.name}</h1>
          </div>
          
    <!-- Stats -->
          <div class="flex items-center gap-4 text-sm">
            <span class="text-base-content/60">{length(@project.agents || [])} agents</span>
            <span class="text-base-content/60">{length(@tasks)} tasks</span>
          </div>
        </div>
        
    <!-- Navigation Tabs -->
        <div class="flex items-center gap-1 -mb-px">
          <.nav_tab
            href={~p"/projects/#{@project.id}"}
            icon="overview"
            label="Overview"
            active={@current_tab == :overview}
          />
          <.nav_tab
            href={~p"/projects/#{@project.id}/files"}
            icon="files"
            label="Files"
            active={@current_tab == :files}
          />
          <.nav_tab
            href={~p"/projects/#{@project.id}/sessions"}
            icon="agents"
            label="Sessions"
            active={@current_tab == :sessions}
          />
          <.nav_tab
            href={~p"/projects/#{@project.id}/prompts"}
            icon="prompts"
            label="Prompts"
            active={@current_tab == :prompts}
          />
          <.nav_tab
            href={~p"/projects/#{@project.id}/tasks"}
            icon="tasks"
            label="Tasks"
            active={@current_tab == :tasks}
          />
          <.nav_tab
            href={~p"/projects/#{@project.id}/kanban"}
            icon="kanban"
            label="Kanban"
            active={@current_tab == :kanban}
          />
          <.nav_tab
            href={~p"/projects/#{@project.id}/notes"}
            icon="notes"
            label="Notes"
            active={@current_tab == :notes}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp nav_tab(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "flex items-center gap-2 px-4 py-2 border-b-2 text-sm transition-colors",
        if(@active,
          do: "border-primary font-medium text-base-content",
          else:
            "border-transparent hover:border-base-content/20 text-base-content/60 hover:text-base-content"
        )
      ]}
    >
      <%= case @icon do %>
        <% "overview" -> %>
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
            <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z" />
          </svg>
        <% "files" -> %>
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
            <path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75Z" />
          </svg>
        <% "agents" -> %>
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
            <path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Zm7-3.25v2.992l2.028.812a.75.75 0 0 1-.557 1.392l-2.5-1A.751.751 0 0 1 7 8.25v-3.5a.75.75 0 0 1 1.5 0Z" />
          </svg>
        <% "prompts" -> %>
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
            <path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Z" />
          </svg>
        <% "tasks" -> %>
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
            <path d="M2.5 1.75v11.5c0 .138.112.25.25.25h3.17a.75.75 0 0 1 .75.75V16L9.4 13.571c.13-.096.289-.196.601-.196h3.249a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25H2.75a.25.25 0 0 0-.25.25Zm-1.5 0C1 .784 1.784 0 2.75 0h10.5C14.216 0 15 .784 15 1.75v11.5A1.75 1.75 0 0 1 13.25 15H10l-3.573 2.573A1.458 1.458 0 0 1 4 16.543V15H2.75A1.75 1.75 0 0 1 1 13.25Z" />
          </svg>
        <% "kanban" -> %>
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
            <path d="M0 1.75C0 .784.784 0 1.75 0h2.5C5.216 0 6 .784 6 1.75v12.5A1.75 1.75 0 0 1 4.25 16h-2.5A1.75 1.75 0 0 1 0 14.25ZM7 1.75C7 .784 7.784 0 8.75 0h2.5C12.216 0 13 .784 13 1.75v7.5A1.75 1.75 0 0 1 11.25 11h-2.5A1.75 1.75 0 0 1 7 9.25ZM14 1.75C14 .784 14.784 0 15.75 0h.5c.966 0 1.75.784 1.75 1.75v4.5A1.75 1.75 0 0 1 16.25 8h-.5A1.75 1.75 0 0 1 14 6.25Z" />
          </svg>
        <% "notes" -> %>
          <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 16 16">
            <path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h12.5a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25ZM3.5 4.75A.75.75 0 0 1 4.25 4h7.5a.75.75 0 0 1 0 1.5h-7.5A.75.75 0 0 1 3.5 4.75ZM4.25 7a.75.75 0 0 0 0 1.5h7.5a.75.75 0 0 0 0-1.5ZM3.5 10.75a.75.75 0 0 1 .75-.75h7.5a.75.75 0 0 1 0 1.5h-7.5a.75.75 0 0 1-.75-.75Z" />
          </svg>
      <% end %>
      {@label}
    </a>
    """
  end
end
