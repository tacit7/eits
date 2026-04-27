defmodule EyeInTheSkyWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality used by your application.
  """
  use EyeInTheSkyWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  # The app.html.heex template provides the sidebar layout.
  embed_templates "layouts/*"

  @doc """
  Desktop-only top bar rendered above `@inner_content`.

  Reads from layout assigns:
  - `sidebar_tab` — atom, drives the section label and toolbar variant
  - `sidebar_project` — Project struct or nil, drives the breadcrumb
  - `top_bar_cta_label` — optional CTA button label
  - `top_bar_cta_href` — if set, CTA renders as a navigate link
  - `top_bar_cta_event` — if set (and no href), CTA renders as a phx-click button

  Tab-specific toolbar assigns (only relevant ones need to be set):
  - Sessions: `search_query`, `session_filter`
  - Tasks: `search_query`, `filter_state_id`, `workflow_states`, `sort_by`
  - Kanban: `search_query`, `show_completed`, `bulk_mode`, `active_filter_count`, `sidebar_project`
  - DM: `dm_active_tab`, `dm_session_name`, `dm_message_search_query`, `dm_active_timer`
  - Notes: `notes_sort_by`, `notes_starred_filter`, `notes_type_filter`, `notes_new_href`
  - Generic: `search_query`

  Hidden on mobile (the mobile header handles that instead).
  """
  attr :sidebar_tab, :atom, default: :sessions
  attr :sidebar_project, :any, default: nil
  # CTA — split attrs eliminate silent failure from raw-map duck-typing
  attr :top_bar_cta_label, :string, default: nil
  attr :top_bar_cta_href, :string, default: nil
  attr :top_bar_cta_event, :string, default: nil
  # Sessions toolbar
  attr :search_query, :string, default: nil
  attr :session_filter, :string, default: nil
  # Tasks toolbar
  attr :filter_state_id, :any, default: nil
  attr :workflow_states, :list, default: nil
  attr :sort_by, :string, default: nil
  # Kanban toolbar
  attr :show_completed, :boolean, default: nil
  attr :bulk_mode, :boolean, default: nil
  attr :active_filter_count, :integer, default: nil
  # Notes toolbar
  attr :notes_sort_by, :string, default: nil
  attr :notes_starred_filter, :boolean, default: false
  attr :notes_type_filter, :string, default: "all"
  attr :notes_new_href, :string, default: nil
  # DM toolbar
  attr :dm_active_tab, :string, default: nil
  attr :dm_session_name, :string, default: nil
  attr :dm_message_search_query, :string, default: nil
  attr :dm_active_timer, :map, default: nil

  @deprecated "Use the top_bar shell in app.html.heex + EyeInTheSkyWeb.TopBar.* modules instead"
  def top_bar(assigns) do
    ~H"""
    <div class="hidden md:flex h-10 flex-shrink-0 items-center gap-2 border-b border-base-content/8 bg-base-100 px-3">
      <%!-- Breadcrumb --%>
      <div class="flex items-center flex-shrink-0">
        <%= if @sidebar_project do %>
          <.link
            navigate={~p"/projects/#{@sidebar_project.id}"}
            class="flex items-center gap-1.5 text-[12px] font-medium text-base-content/50 hover:text-base-content/75 hover:bg-base-content/5 px-1.5 py-1 rounded-md transition-colors"
          >
            <.icon name="hero-folder" class="w-3 h-3" />
            {@sidebar_project.name}
          </.link>
          <span class="text-base-content/20 text-sm mx-1 select-none">/</span>
        <% end %>
        <span class="text-[12px] font-semibold text-base-content/75 px-1">
          <%= if @sidebar_tab == :dm && @dm_session_name do %>
            {@dm_session_name}
          <% else %>
            {top_bar_section_label(@sidebar_tab)}
          <% end %>
        </span>
      </div>

      <%= cond do %>
        <% @sidebar_tab == :notes && not is_nil(@notes_sort_by) -> %>
          <.notes_toolbar {assigns} />
        <% @sidebar_tab == :dm && not is_nil(@dm_active_tab) -> %>
          <.dm_toolbar {assigns} />
        <% @sidebar_tab == :sessions && not is_nil(@session_filter) -> %>
          <.sessions_toolbar {assigns} />
        <% @sidebar_tab == :tasks && not is_nil(@workflow_states) -> %>
          <.tasks_toolbar {assigns} />
        <% @sidebar_tab == :kanban && not is_nil(@show_completed) -> %>
          <.kanban_toolbar {assigns} />
        <% not is_nil(@search_query) -> %>
          <.generic_search_toolbar {assigns} />
        <% true -> %>
          <.default_toolbar {assigns} />
      <% end %>

      <%!-- Optional CTA: link or button depending on which attr is set --%>
      <%= if @top_bar_cta_label do %>
        <%= if @top_bar_cta_href do %>
          <.link
            navigate={@top_bar_cta_href}
            class="ml-auto flex items-center gap-1 h-7 px-2.5 rounded-md text-[11px] font-medium bg-primary text-primary-content hover:bg-primary/90 transition-colors"
          >
            <.icon name="hero-plus" class="w-3 h-3" />
            {@top_bar_cta_label}
          </.link>
        <% else %>
          <button
            phx-click={@top_bar_cta_event}
            class="ml-auto flex items-center gap-1 h-7 px-2.5 rounded-md text-[11px] font-medium bg-primary text-primary-content hover:bg-primary/90 transition-colors"
          >
            <.icon name="hero-plus" class="w-3 h-3" />
            {@top_bar_cta_label}
          </button>
        <% end %>
      <% end %>
    </div>
    """
  end

  # ── Public top bar helpers (used by app.html.heex shell) ────────────────────

  @doc "Breadcrumb slot: project link + section label (or DM session name)."
  attr :sidebar_tab, :atom, required: true
  attr :sidebar_project, :any, default: nil
  attr :dm_session_name, :string, default: nil

  def top_bar_breadcrumb(assigns) do
    ~H"""
    <div class="flex items-center flex-shrink-0">
      <%= if @sidebar_project do %>
        <.link
          navigate={~p"/projects/#{@sidebar_project.id}"}
          class="flex items-center gap-1.5 text-[12px] font-medium text-base-content/50 hover:text-base-content/75 hover:bg-base-content/5 px-1.5 py-1 rounded-md transition-colors"
        >
          <.icon name="hero-folder" class="w-3 h-3" />
          {@sidebar_project.name}
        </.link>
        <span class="text-base-content/20 text-sm mx-1 select-none">/</span>
      <% end %>
      <span class="text-[12px] font-semibold text-base-content/75 px-1">
        <%= if @sidebar_tab == :dm && @dm_session_name do %>
          {@dm_session_name}
        <% else %>
          {top_bar_section_label(@sidebar_tab)}
        <% end %>
      </span>
    </div>
    """
  end

  @doc "CTA button slot: renders a primary + button (link or phx-click)."
  attr :label, :string, default: nil
  attr :href, :string, default: nil
  attr :event, :string, default: nil

  def top_bar_cta(assigns) do
    ~H"""
    <%= if @label do %>
      <%= if @href do %>
        <.link
          navigate={@href}
          class="ml-auto flex items-center gap-1 h-7 px-2.5 rounded-md text-[11px] font-medium bg-primary text-primary-content hover:bg-primary/90 transition-colors"
        >
          <.icon name="hero-plus" class="w-3 h-3" />
          {@label}
        </.link>
      <% else %>
        <button
          phx-click={@event}
          class="ml-auto flex items-center gap-1 h-7 px-2.5 rounded-md text-[11px] font-medium bg-primary text-primary-content hover:bg-primary/90 transition-colors"
        >
          <.icon name="hero-plus" class="w-3 h-3" />
          {@label}
        </button>
      <% end %>
    <% end %>
    """
  end

  # ── Private toolbar sub-components ──────────────────────────────────────────

  defp dm_toolbar(assigns) do
    ~H"""
    <%!-- DM: search first, then tab pills --%>
    <%= if @dm_active_tab in ["messages", nil] && not is_nil(@dm_message_search_query) do %>
      <form phx-change="search_messages" phx-submit="search_messages" class="w-48">
        <div class="relative">
          <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-2.5">
            <.icon name="hero-magnifying-glass-mini" class="w-3.5 h-3.5 text-base-content/30" />
          </div>
          <input
            type="text"
            name="query"
            value={@dm_message_search_query}
            placeholder="Search messages..."
            autocomplete="off"
            phx-debounce="300"
            class="input input-xs w-full pl-8 h-7 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-[12px]"
          />
        </div>
      </form>
    <% end %>
    <div class="flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
      <%= for {tab, label} <- [
        {"messages", "Messages"},
        {"tasks", "Tasks"},
        {"commits", "Commits"},
        {"notes", "Notes"},
        {"context", "Context"},
        {"settings", "Settings"}
      ] do %>
        <button
          phx-click="change_tab"
          phx-value-tab={tab}
          class={"px-2.5 py-1 rounded-md text-[11px] font-medium transition-all duration-150 " <>
            if(@dm_active_tab == tab,
              do: "bg-base-100 text-base-content shadow-sm",
              else: "text-base-content/45 hover:text-base-content/70"
            )}
        >
          {label}
        </button>
      <% end %>
    </div>
    <div class="flex-1" />
    <%!-- ... menu --%>
    <div class="dropdown dropdown-end">
      <button
        tabindex="0"
        class="btn btn-ghost btn-square w-7 h-7 text-base-content/50 hover:text-base-content/75"
        aria-label="More options"
      >
        <.icon name="hero-ellipsis-horizontal" class="w-4 h-4" />
      </button>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-100 rounded-box border border-base-content/10 shadow-lg z-50 p-1 w-48 text-xs"
      >
        <li>
          <button
            phx-click={JS.dispatch("dm:reload-check", to: "#dm-reload-confirm-modal")}
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> Reload
          </button>
        </li>
        <li>
          <button
            phx-click="export_markdown"
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Export as Markdown
          </button>
        </li>
        <li><div class="divider my-0"></div></li>
        <li>
          <button
            phx-click="open_schedule_timer"
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
          >
            <.icon name="hero-clock" class="w-3.5 h-3.5" /> Schedule Message
          </button>
        </li>
        <%= if @dm_active_timer do %>
          <li>
            <button
              phx-click="cancel_timer"
              class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-error/10 text-error rounded"
            >
              <.icon name="hero-x-circle" class="w-3.5 h-3.5" /> Cancel Schedule
            </button>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp notes_toolbar(assigns) do
    ~H"""
    <%!-- Notes: search + quick note + starred + type + sort --%>
    <form phx-change="search" class="w-44">
      <label for="notes-top-bar-search" class="sr-only">Search notes</label>
      <div class="relative">
        <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-2.5">
          <.icon name="hero-magnifying-glass-mini" class="w-3.5 h-3.5 text-base-content/30" />
        </div>
        <input
          type="text"
          id="notes-top-bar-search"
          name="query"
          value={@search_query || ""}
          phx-debounce="300"
          placeholder="Search notes..."
          autocomplete="off"
          class="input input-xs w-full pl-8 h-7 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-[12px]"
        />
      </div>
    </form>
    <button
      phx-click="open_quick_note_modal"
      class="flex items-center gap-1 h-7 px-2.5 rounded-md text-[11px] font-medium text-base-content/60 hover:text-base-content hover:bg-base-content/8 transition-colors"
    >
      <.icon name="hero-bolt" class="w-3 h-3" /> Quick Note
    </button>
    <div class="w-px h-4 bg-base-content/10 mx-0.5" />
    <button
      phx-click="toggle_starred_filter"
      aria-label={if @notes_starred_filter, do: "Remove starred filter", else: "Filter by starred"}
      class={"flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium transition-colors " <>
        if(@notes_starred_filter,
          do: "bg-warning/10 text-warning",
          else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/8"
        )}
    >
      <.icon
        name={if @notes_starred_filter, do: "hero-star-solid", else: "hero-star"}
        class="w-3.5 h-3.5"
      />
    </button>
    <details id="notes-type-dropdown" phx-update="ignore" class="dropdown">
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Type: {case @notes_type_filter do
          "session" -> "Session"
          "agent" -> "Agent"
          "project" -> "Project"
          "task" -> "Task"
          "system" -> "System"
          _ -> "All"
        end} <.icon name="hero-chevron-down-mini" class="w-3 h-3 opacity-50" />
      </summary>
      <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[120px]">
        <%= for {value, label} <- [{"all", "All"}, {"session", "Session"}, {"agent", "Agent"}, {"project", "Project"}, {"task", "Task"}, {"system", "System"}] do %>
          <li>
            <button
              phx-click="filter_type"
              phx-value-value={value}
              onclick="this.closest('details').removeAttribute('open')"
              class={"block w-full px-3 py-1.5 text-left text-[11px] rounded hover:bg-base-content/5 " <>
                if(@notes_type_filter == value, do: "text-base-content font-medium", else: "text-base-content/60")}
            >
              {label}
            </button>
          </li>
        <% end %>
      </ul>
    </details>
    <details id="notes-sort-dropdown" phx-update="ignore" class="dropdown">
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Sort: {if @notes_sort_by == "oldest", do: "Oldest", else: "Newest"} <.icon name="hero-chevron-down-mini" class="w-3 h-3 opacity-50" />
      </summary>
      <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[120px]">
        <%= for {value, label} <- [{"newest", "Newest"}, {"oldest", "Oldest"}] do %>
          <li>
            <button
              phx-click="sort_notes"
              phx-value-value={value}
              onclick="this.closest('details').removeAttribute('open')"
              class={"block w-full px-3 py-1.5 text-left text-[11px] rounded hover:bg-base-content/5 " <>
                if(@notes_sort_by == value, do: "text-base-content font-medium", else: "text-base-content/60")}
            >
              {label}
            </button>
          </li>
        <% end %>
      </ul>
    </details>
    <%= if @notes_new_href do %>
      <.link
        navigate={@notes_new_href}
        class="ml-auto flex items-center gap-1 h-7 px-2.5 rounded-md text-[11px] font-medium bg-primary text-primary-content hover:bg-primary/90 transition-colors"
      >
        <.icon name="hero-plus" class="w-3 h-3" /> New Note
      </.link>
    <% end %>
    """
  end

  defp sessions_toolbar(assigns) do
    ~H"""
    <%!-- Sessions: inline search + filter tabs + sort --%>
    <form phx-change="search" class="flex-1 max-w-xs">
      <label for="top-bar-search" class="sr-only">Search</label>
      <div class="relative">
        <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-2.5">
          <.icon name="hero-magnifying-glass-mini" class="w-3.5 h-3.5 text-base-content/30" />
        </div>
        <input
          type="text"
          name="query"
          id="top-bar-search"
          value={@search_query || ""}
          phx-debounce="300"
          placeholder="Search..."
          autocomplete="off"
          class="input input-xs w-full pl-8 h-7 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-[12px]"
        />
      </div>
    </form>
    <div class="flex items-center gap-0.5 bg-base-200/40 rounded-lg p-0.5">
      <%= for {value, label} <- [{"all", "All"}, {"working", "Working"}, {"archived", "Archived"}] do %>
        <button
          phx-click="filter_session"
          phx-value-filter={value}
          class={"px-2.5 py-1 rounded-md text-[11px] font-medium transition-all duration-150 " <>
            if(@session_filter == value,
              do: "bg-base-100 text-base-content shadow-sm",
              else: "text-base-content/45 hover:text-base-content/70"
            )}
        >
          {label}
        </button>
      <% end %>
    </div>
    <details id="sessions-sort-dropdown" phx-update="ignore" class="dropdown">
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Sort: {case @sort_by do
          "last_message" -> "Last msg"
          "name" -> "Name"
          "agent" -> "Agent"
          "model" -> "Model"
          _ -> "Last msg"
        end} <.icon name="hero-chevron-down-mini" class="w-3 h-3 opacity-50" />
      </summary>
      <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[120px]">
        <%= for {value, label} <- [{"last_message", "Last msg"}, {"name", "Name"}, {"agent", "Agent"}, {"model", "Model"}] do %>
          <li>
            <button
              phx-click="sort"
              phx-value-by={value}
              onclick="this.closest('details').removeAttribute('open')"
              class={"block w-full px-3 py-1.5 text-left text-[11px] rounded hover:bg-base-content/5 " <>
                if(@sort_by == value, do: "text-base-content font-medium", else: "text-base-content/60")}
            >
              {label}
            </button>
          </li>
        <% end %>
      </ul>
    </details>
    """
  end

  defp tasks_toolbar(assigns) do
    ~H"""
    <%!-- Tasks: search + state filter pills + sort --%>
    <form phx-change="search" class="flex-1 max-w-xs">
      <label for="top-bar-tasks-search" class="sr-only">Search tasks</label>
      <div class="relative">
        <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-2.5">
          <.icon name="hero-magnifying-glass-mini" class="w-3.5 h-3.5 text-base-content/30" />
        </div>
        <input
          type="text"
          name="query"
          id="top-bar-tasks-search"
          value={@search_query || ""}
          phx-debounce="300"
          placeholder="Search tasks..."
          autocomplete="off"
          class="input input-xs w-full pl-8 h-7 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-[12px]"
        />
      </div>
    </form>
    <div class="flex items-center gap-0.5 bg-base-200/40 rounded-lg p-0.5">
      <button
        phx-click="filter_status"
        phx-value-state_id=""
        class={"px-2.5 py-1 rounded-md text-[11px] font-medium transition-all duration-150 " <>
          if(is_nil(@filter_state_id),
            do: "bg-base-100 text-base-content shadow-sm",
            else: "text-base-content/45 hover:text-base-content/70"
          )}
      >
        All
      </button>
      <%= for state <- @workflow_states do %>
        <button
          phx-click="filter_status"
          phx-value-state_id={state.id}
          class={"px-2.5 py-1 rounded-md text-[11px] font-medium transition-all duration-150 " <>
            if(@filter_state_id == state.id,
              do: "bg-base-100 text-base-content shadow-sm",
              else: "text-base-content/45 hover:text-base-content/70"
            )}
        >
          {state.name}
        </button>
      <% end %>
    </div>
    <details id="tasks-sort-dropdown" phx-update="ignore" class="dropdown">
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Sort: {case @sort_by do
          "created_desc" -> "Newest"
          "created_asc" -> "Oldest"
          "priority" -> "Priority"
          _ -> "Newest"
        end} <.icon name="hero-chevron-down-mini" class="w-3 h-3 opacity-50" />
      </summary>
      <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[120px]">
        <%= for {value, label} <- [{"created_desc", "Newest"}, {"created_asc", "Oldest"}, {"priority", "Priority"}] do %>
          <li>
            <button
              phx-click="sort_by"
              phx-value-value={value}
              onclick="this.closest('details').removeAttribute('open')"
              class={"block w-full px-3 py-1.5 text-left text-[11px] rounded hover:bg-base-content/5 " <>
                if(@sort_by == value, do: "text-base-content font-medium", else: "text-base-content/60")}
            >
              {label}
            </button>
          </li>
        <% end %>
      </ul>
    </details>
    """
  end

  defp kanban_toolbar(assigns) do
    ~H"""
    <%!-- Kanban: search + action buttons --%>
    <form phx-change="search" class="flex-1 max-w-xs">
      <label for="top-bar-kanban-search" class="sr-only">Search tasks</label>
      <div class="relative">
        <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-2.5">
          <.icon name="hero-magnifying-glass-mini" class="w-3.5 h-3.5 text-base-content/30" />
        </div>
        <input
          type="text"
          name="query"
          id="top-bar-kanban-search"
          value={@search_query || ""}
          phx-debounce="300"
          placeholder="Search tasks..."
          autocomplete="off"
          class="input input-xs w-full pl-8 h-7 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-[12px]"
        />
      </div>
    </form>
    <div class="flex items-center gap-1">
      <button
        phx-click="toggle_show_completed"
        class={"flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium transition-colors " <>
          if(@show_completed,
            do: "bg-base-content/10 text-base-content",
            else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/6"
          )}
        title="Show completed tasks"
      >
        <.icon name="hero-check-circle-mini" class="w-3.5 h-3.5" /> Done
      </button>
      <button
        phx-click="toggle_bulk_mode"
        class={"flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium transition-colors " <>
          if(@bulk_mode,
            do: "bg-base-content/10 text-base-content",
            else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/6"
          )}
        title="Bulk select"
      >
        <.icon name="hero-check-mini" class="w-3.5 h-3.5" /> Select
      </button>
      <button
        phx-click="toggle_filter_drawer"
        class={"flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium transition-colors " <>
          if(@active_filter_count && @active_filter_count > 0,
            do: "bg-base-content/10 text-base-content",
            else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/6"
          )}
        title="Filter"
      >
        <.icon name="hero-funnel-mini" class="w-3.5 h-3.5" />
        Filter
        <%= if @active_filter_count && @active_filter_count > 0 do %>
          <span class="inline-flex items-center justify-center w-4 h-4 rounded-full bg-primary text-primary-content text-[9px] font-bold">
            {@active_filter_count}
          </span>
        <% end %>
      </button>
      <%= if @sidebar_project do %>
        <.link
          navigate={~p"/projects/#{@sidebar_project.id}/tasks"}
          class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium text-base-content/45 hover:text-base-content/70 hover:bg-base-content/6 transition-colors"
          title="List view"
        >
          <.icon name="hero-list-bullet-mini" class="w-3.5 h-3.5" /> List
        </.link>
      <% end %>
    </div>
    """
  end

  defp generic_search_toolbar(assigns) do
    ~H"""
    <%!-- Generic search — skills, prompts, teams, notes, etc. --%>
    <form phx-change="search" class="flex-1 max-w-xs">
      <label for="top-bar-generic-search" class="sr-only">Search</label>
      <div class="relative">
        <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-2.5">
          <.icon name="hero-magnifying-glass-mini" class="w-3.5 h-3.5 text-base-content/30" />
        </div>
        <input
          type="text"
          name="query"
          id="top-bar-generic-search"
          value={@search_query}
          phx-debounce="300"
          placeholder="Search..."
          autocomplete="off"
          class="input input-xs w-full pl-8 h-7 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-[12px]"
        />
      </div>
    </form>
    """
  end

  defp default_toolbar(assigns) do
    ~H"""
    <%!-- Default: spacer + palette search button --%>
    <div class="flex-1" />
    <button
      phx-click={JS.dispatch("palette:open", to: "#command-palette")}
      class="flex items-center gap-1.5 h-7 px-2.5 rounded-md text-[11px] font-medium text-base-content/45 hover:text-base-content/70 hover:bg-base-content/6 transition-colors"
      title="Search"
      aria-label="Search"
    >
      <.icon name="hero-magnifying-glass" class="w-3.5 h-3.5" />
      Search
      <kbd class="ml-0.5 inline-flex items-center px-1 py-0.5 rounded text-[9px] bg-base-content/8 text-base-content/30 border border-base-content/10 font-sans leading-none">
        ⌘K
      </kbd>
    </button>
    """
  end

  @doc false
  def top_bar_section_label(:dm), do: "Session"
  def top_bar_section_label(:agents), do: "Agents"
  def top_bar_section_label(:sessions), do: "Sessions"
  def top_bar_section_label(:overview), do: "Sessions"
  def top_bar_section_label(:tasks), do: "Tasks"
  def top_bar_section_label(:kanban), do: "Tasks"
  def top_bar_section_label(:prompts), do: "Prompts"
  def top_bar_section_label(:notes), do: "Notes"
  def top_bar_section_label(:skills), do: "Skills"
  def top_bar_section_label(:teams), do: "Teams"
  def top_bar_section_label(:canvas), do: "Canvas"
  def top_bar_section_label(:chat), do: "Chat"
  def top_bar_section_label(:notifications), do: "Notifications"
  def top_bar_section_label(:usage), do: "Usage"
  def top_bar_section_label(:jobs), do: "Jobs"
  def top_bar_section_label(:config), do: "Config"
  def top_bar_section_label(:settings), do: "Settings"
  def top_bar_section_label(:files), do: "Files"
  def top_bar_section_label(:iam), do: "IAM"
  def top_bar_section_label(_), do: ""

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <%!-- Toast notifications (put_flash :info / :error) are disabled.
           Connection-status banners below are kept. --%>
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
