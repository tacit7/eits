defmodule EyeInTheSkyWeb.Components.ProjectSessionsFilters do
  @moduledoc false
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents

  @doc "Sticky search + filter + sort toolbar."
  attr :search_query, :string, required: true
  attr :session_filter, :string, required: true
  attr :sort_by, :string, required: true

  def filter_bar(assigns) do
    ~H"""
    <div class="sticky safe-top-sticky md:top-16 z-10 bg-base-100/85 backdrop-blur-md -mx-4 sm:-mx-6 lg:-mx-8 px-4 sm:px-6 lg:px-8 py-3 border-b border-base-content/5">
      <div class="flex items-center gap-3">
        <form phx-submit="search" phx-change="search" class="flex-1 sm:max-w-sm">
          <div class="relative">
            <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
              <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
            </div>
            <label for="project-sessions-search" class="sr-only">Search sessions</label>
            <input
              type="text"
              name="query"
              id="project-sessions-search"
              value={@search_query}
              phx-debounce="300"
              class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-base"
              placeholder="Search..."
            />
          </div>
        </form>

        <%!-- Desktop filter pills --%>
        <div class="hidden sm:flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
          <%= for {label, filter, active_class} <- [
            {"All", "all", "bg-base-100 text-base-content shadow-sm"},
            {"Active", "active", "bg-base-100 text-success shadow-sm"},
            {"Completed", "completed", "bg-base-100 text-base-content shadow-sm"},
            {"Archived", "archived", "bg-base-100 text-warning shadow-sm"}
          ] do %>
            <button
              phx-click="filter_session"
              phx-value-filter={filter}
              aria-pressed={@session_filter == filter}
              class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                if(@session_filter == filter,
                  do: active_class,
                  else: "text-base-content/60 hover:text-base-content/85"
                )}
            >
              {label}
            </button>
          <% end %>
        </div>

        <%!-- Desktop sort pills --%>
        <div class="hidden sm:flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
          <%= for {label, sort} <- [
            {"Last msg", "last_message"},
            {"Created", "created"},
            {"Name", "name"}
          ] do %>
            <button
              phx-click="sort"
              phx-value-by={sort}
              aria-pressed={@sort_by == sort}
              class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                if(@sort_by == sort,
                  do: "bg-base-100 text-base-content shadow-sm",
                  else: "text-base-content/60 hover:text-base-content/85"
                )}
            >
              {label}
            </button>
          <% end %>
        </div>

        <%!-- Mobile filter button --%>
        <button
          phx-click="open_filter_sheet"
          aria-label="Open filters"
          aria-haspopup="dialog"
          class="sm:hidden relative btn btn-ghost btn-sm btn-square min-h-[44px] min-w-[44px]"
        >
          <.icon name="hero-funnel-mini" class="w-4 h-4" />
          <%= if @session_filter != "all" || @sort_by != "last_message" do %>
            <span class="absolute top-0.5 right-0.5 w-2 h-2 bg-primary rounded-full" aria-hidden="true">
            </span>
          <% end %>
        </button>
      </div>
    </div>
    """
  end

  @doc "Mobile bottom sheet for filter/sort."
  attr :session_filter, :string, required: true
  attr :sort_by, :string, required: true

  def filter_sheet(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-40 bg-black/40"
      phx-click="close_filter_sheet"
      aria-hidden="true"
    >
    </div>
    <div
      class="fixed inset-x-0 bottom-0 z-50 rounded-t-2xl bg-base-100 shadow-xl safe-bottom-sheet"
      role="dialog"
      aria-modal="true"
      aria-label="Filter sessions"
      id="session-filter-sheet"
      phx-window-keydown="close_filter_sheet"
      phx-key="Escape"
    >
      <div class="flex justify-center pt-3 pb-1">
        <div class="w-10 h-1 rounded-full bg-base-content/20"></div>
      </div>
      <div class="px-5 pb-6 pt-2">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-sm font-semibold">Filter &amp; Sort</h2>
          <button
            phx-click="close_filter_sheet"
            class="btn btn-ghost btn-xs btn-square"
            aria-label="Close filter panel"
          >
            <.icon name="hero-x-mark-mini" class="w-4 h-4" />
          </button>
        </div>

        <fieldset class="mb-5">
          <legend class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-2">
            Status
          </legend>
          <div class="flex flex-wrap gap-2">
            <%= for {label, filter} <- [
              {"All", "all"},
              {"Active", "active"},
              {"Completed", "completed"},
              {"Archived", "archived"}
            ] do %>
              <button
                phx-click="filter_session"
                phx-value-filter={filter}
                aria-pressed={@session_filter == filter}
                class={"btn btn-sm " <>
                  if(@session_filter == filter,
                    do: "btn-primary",
                    else: "btn-ghost border border-base-content/15"
                  )}
              >
                {label}
              </button>
            <% end %>
          </div>
        </fieldset>

        <fieldset class="mb-6">
          <legend class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-2">
            Sort by
          </legend>
          <div class="flex flex-wrap gap-2">
            <%= for {label, sort} <- [{"Last Message", "last_message"}, {"Created", "created"}, {"Name", "name"}, {"Status", "status"}] do %>
              <button
                phx-click="sort"
                phx-value-by={sort}
                aria-pressed={@sort_by == sort}
                class={"btn btn-sm " <>
                  if(@sort_by == sort,
                    do: "btn-primary",
                    else: "btn-ghost border border-base-content/15"
                  )}
              >
                {label}
              </button>
            <% end %>
          </div>
        </fieldset>

        <div class="flex gap-3">
          <button phx-click="close_filter_sheet" class="btn btn-primary flex-1">Apply</button>
          <button
            phx-click="filter_session"
            phx-value-filter="all"
            class="btn btn-ghost"
            aria-label="Reset filters"
          >
            Reset
          </button>
        </div>
      </div>
    </div>
    """
  end
end
