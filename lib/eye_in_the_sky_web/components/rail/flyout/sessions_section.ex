defmodule EyeInTheSkyWeb.Components.Rail.Flyout.SessionsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [relative_time: 1]

  # ---------------------------------------------------------------------------
  # sessions_filters — scope toggle + search
  # ---------------------------------------------------------------------------

  attr :session_name_filter, :string, default: ""
  attr :session_scope, :atom, default: :current
  attr :myself, :any, required: true

  def sessions_filters(assigns) do
    ~H"""
    <div class="px-2.5 py-2 border-b border-base-content/8 flex flex-col gap-2">
      <%!-- Search --%>
      <div class="relative">
        <span class="absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none">
          <.icon name="hero-magnifying-glass-mini" class="size-3" />
        </span>
        <input
          type="text"
          value={@session_name_filter}
          placeholder="Search sessions…"
          phx-keyup="update_session_name_filter"
          phx-target={@myself}
          phx-debounce="200"
          class="w-full pl-6 pr-2 py-1 text-xs bg-base-content/[0.04] border border-base-content/[0.15] rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/35"
        />
      </div>
      <%!-- Scope toggle --%>
      <div class="flex gap-0.5">
        <.scope_pill label="Current" value="current" current={@session_scope} myself={@myself} />
        <.scope_pill label="All Projects" value="all" current={@session_scope} myself={@myself} />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :current, :atom, default: :current
  attr :myself, :any, required: true

  defp scope_pill(assigns) do
    ~H"""
    <% active = to_string(@current) == @value %>
    <button
      phx-click="set_session_scope"
      phx-value-scope={@value}
      phx-target={@myself}
      class={[
        "text-nano px-2 py-0.5 rounded transition-colors",
        if(active,
          do: "bg-primary/15 text-primary font-medium",
          else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/8"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # sessions_content
  # ---------------------------------------------------------------------------

  attr :sessions, :list, required: true
  attr :session_name_filter, :string, default: ""
  attr :session_scope, :atom, default: :current
  attr :projects, :list, default: []
  attr :session_project_visible, :map, default: %{}
  attr :session_project_collapsed, :any, default: nil
  attr :sidebar_project, :any, default: nil
  attr :myself, :any, required: true

  def sessions_content(assigns) do
    is_searching = assigns.session_name_filter != ""

    sessions_by_project =
      if assigns.session_scope == :all do
        Enum.group_by(assigns.sessions, & &1.project_id)
      else
        %{}
      end

    view_all_href =
      if assigns.sidebar_project,
        do: "/projects/#{assigns.sidebar_project.id}/sessions",
        else: "/sessions"

    assigns =
      assigns
      |> assign(:is_searching, is_searching)
      |> assign(:sessions_by_project, sessions_by_project)
      |> assign(:view_all_href, view_all_href)

    ~H"""
    <div class="flex flex-col flex-1 min-h-0">
      <div class="flex-1 min-h-0 overflow-y-auto">
        <%= if @session_scope == :all do %>
          <.all_projects_content
            projects={@projects}
            sessions_by_project={@sessions_by_project}
            session_project_visible={@session_project_visible}
            session_project_collapsed={@session_project_collapsed || MapSet.new()}
            session_name_filter={@session_name_filter}
            myself={@myself}
          />
        <% else %>
          <.current_content
            sessions={@sessions}
            is_searching={@is_searching}
          />
        <% end %>
      </div>

      <%!-- View all link --%>
      <div class="flex-shrink-0 px-3 py-2 border-t border-base-content/[0.05]">
        <.link
          navigate={@view_all_href}
          class="flex items-center gap-1 text-[11px] text-base-content/30 hover:text-base-content/55 transition-colors group select-none"
        >
          <.icon
            name="hero-arrow-right-mini"
            class="size-3 group-hover:translate-x-0.5 transition-transform duration-100"
          /> View all sessions
        </.link>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # current_content — flat list, 30 sessions, no group labels
  # ---------------------------------------------------------------------------

  attr :sessions, :list, required: true
  attr :is_searching, :boolean, required: true

  defp current_content(assigns) do
    ~H"""
    <%= if @sessions == [] do %>
      <div class="px-3 py-5 text-xs text-base-content/35 text-center select-none">
        {if @is_searching, do: "No sessions found", else: "No sessions"}
      </div>
    <% else %>
      <.session_row :for={s <- @sessions} session={s} />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # all_projects_content — grouped by project
  # ---------------------------------------------------------------------------

  attr :projects, :list, required: true
  attr :sessions_by_project, :map, required: true
  attr :session_project_visible, :map, required: true
  attr :session_project_collapsed, :any, required: true
  attr :session_name_filter, :string, default: ""
  attr :myself, :any, required: true

  defp all_projects_content(assigns) do
    ~H"""
    <%= if @projects == [] do %>
      <div class="px-3 py-5 text-xs text-base-content/35 text-center select-none">
        No projects
      </div>
    <% else %>
      <div :for={project <- @projects}>
        <% project_sessions = Map.get(@sessions_by_project, project.id, []) %>
        <% collapsed = MapSet.member?(@session_project_collapsed, project.id) %>
        <% visible = Map.get(@session_project_visible, project.id, 5) %>
        <% shown = if collapsed, do: [], else: Enum.take(project_sessions, visible) %>
        <% has_more = not collapsed and length(project_sessions) > visible %>
        <%!-- Project header — click to collapse/expand --%>
        <div class="flex items-center justify-between px-3 pt-3 pb-1 group/proj select-none">
          <button
            phx-click="toggle_project_sessions"
            phx-value-project_id={project.id}
            phx-target={@myself}
            class="flex items-center gap-1.5 min-w-0 flex-1 text-left hover:text-base-content/80 transition-colors"
          >
            <.icon
              name={if collapsed, do: "hero-folder-mini", else: "hero-folder-open-mini"}
              class="size-3 text-base-content/35 flex-shrink-0"
            />
            <span class="text-nano font-semibold text-base-content/55 truncate">
              {project.name}
            </span>
          </button>
          <.link
            navigate={"/projects/#{project.id}/sessions"}
            title="Open sessions"
            class="text-base-content/20 hover:text-base-content/55 transition-colors flex-shrink-0 opacity-0 group-hover/proj:opacity-100"
          >
            <.icon name="hero-pencil-square-mini" class="size-3" />
          </.link>
        </div>
        <%!-- Sessions --%>
        <%= if not collapsed do %>
          <%= if shown == [] do %>
            <div class="px-4 pb-2 text-nano text-base-content/30 italic select-none">
              No sessions
            </div>
          <% else %>
            <.session_row :for={s <- shown} session={s} />
          <% end %>
          <%!-- Show more --%>
          <%= if has_more do %>
            <button
              phx-click="show_more_project_sessions"
              phx-value-project_id={project.id}
              phx-target={@myself}
              class="w-full px-4 pb-2 text-left text-nano text-base-content/35 hover:text-primary/70 transition-colors select-none"
            >
              Show more
            </button>
          <% end %>
        <% end %>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # session_row
  # ---------------------------------------------------------------------------

  attr :session, :map, required: true

  def session_row(assigns) do
    ~H"""
    <.link
      navigate={"/dm/#{@session.id}"}
      data-vim-flyout-item
      class="flyout-session-row flex items-start gap-2 px-3 py-1.5 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-[var(--surface-hover,theme(colors.base-content/6%))] transition-colors [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded [&.active]:font-semibold [&.active]:text-base-content/92 [&.active]:bg-[var(--surface-selected,theme(colors.primary/12%))] [&.active]:border-l-2 [&.active]:border-primary/80 [&.active]:pl-[10px]"
    >
      <.status_dot status={@session.status} size="xs" class="mt-[3px] flex-shrink-0" />
      <div class="min-w-0 flex-1">
        <div class="session-row-name truncate font-medium text-xs text-base-content/75 [.active_&]:font-semibold [.active_&]:text-base-content/92">
          {@session.name || "unnamed"}
        </div>
        <div class="text-nano text-base-content/48 mt-0.5 flex items-center gap-1">
          <span class="text-base-content/30">#{@session.id}</span>
          <span>·</span>
          <span class="capitalize">{@session.status}</span>
          <%= if @session.last_activity_at do %>
            <span>·</span>
            <span>{relative_time(@session.last_activity_at)}</span>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end
end
