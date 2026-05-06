defmodule EyeInTheSkyWeb.Components.Rail.Flyout.SessionsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [relative_time: 1]

  @active_statuses ~w(working waiting compacting)

  # ---------------------------------------------------------------------------
  # sessions_filters — search only (sort + show controls removed; those belong
  # on the full Sessions page, not the compact DM switcher)
  # ---------------------------------------------------------------------------

  attr :session_name_filter, :string, default: ""
  attr :myself, :any, required: true

  def sessions_filters(assigns) do
    ~H"""
    <div class="px-2.5 py-2 border-b border-base-content/8">
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
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # sessions_content — grouped switcher view
  # ---------------------------------------------------------------------------

  attr :sessions, :list, required: true
  attr :session_name_filter, :string, default: ""
  attr :sidebar_project, :any, default: nil

  def sessions_content(assigns) do
    is_searching = assigns.session_name_filter != ""

    {active, recent, results} =
      if is_searching do
        {[], [], Enum.take(assigns.sessions, 10)}
      else
        a = assigns.sessions |> Enum.filter(&(&1.status in @active_statuses)) |> Enum.take(5)
        r = assigns.sessions |> Enum.reject(&(&1.status in @active_statuses)) |> Enum.take(8)
        {a, r, []}
      end

    view_all_href =
      if assigns.sidebar_project,
        do: "/projects/#{assigns.sidebar_project.id}/sessions",
        else: "/sessions"

    assigns =
      assigns
      |> assign(:is_searching, is_searching)
      |> assign(:active, active)
      |> assign(:recent, recent)
      |> assign(:results, results)
      |> assign(:view_all_href, view_all_href)

    ~H"""
    <div class="flex flex-col flex-1 min-h-0">
      <div class="flex-1 min-h-0 overflow-y-auto">
        <%= if @is_searching do %>
          <%!--Search results --%>
          <%= if @results == [] do %>
            <div class="px-3 py-5 text-xs text-base-content/35 text-center select-none">
              No sessions found
            </div>
          <% else %>
            <.session_row :for={s <- @results} session={s} />
          <% end %>
        <% else %>
          <%!--ACTIVE group --%>
          <%= if @active != [] do %>
            <.group_label label="Active" />
            <.session_row :for={s <- @active} session={s} />
          <% end %>
          <%!--RECENT group --%>
          <%= if @recent != [] do %>
            <.group_label label="Recent" />
            <.session_row :for={s <- @recent} session={s} />
          <% end %>
          <%!--Both empty --%>
          <%= if @active == [] && @recent == [] do %>
            <div class="px-3 py-5 text-xs text-base-content/35 text-center select-none">
              No sessions
            </div>
          <% end %>
        <% end %>
      </div>

      <%!--View all link — always visible at bottom --%>
      <div class="flex-shrink-0 px-3 py-2 border-t border-base-content/[0.05]">
        <.link
          navigate={@view_all_href}
          class="flex items-center gap-1 text-[11px] text-base-content/30 hover:text-base-content/55 transition-colors group select-none"
        >
          <.icon name="hero-arrow-right-mini" class="size-3 group-hover:translate-x-0.5 transition-transform duration-100" />
          View all sessions
        </.link>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # group_label — ACTIVE / RECENT section header
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true

  defp group_label(assigns) do
    ~H"""
    <div class="px-3 pt-3 pb-1 flex items-center gap-1.5 select-none">
      <span class="w-[2px] h-[10px] rounded-sm bg-primary/50 flex-shrink-0"></span>
      <span class="text-nano font-extrabold uppercase tracking-[0.10em] text-primary/70">
        {@label}
      </span>
    </div>
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
