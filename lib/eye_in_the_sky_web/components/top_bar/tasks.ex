defmodule EyeInTheSkyWeb.TopBar.Tasks do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  attr :search_query, :string, default: nil
  attr :filter_state_id, :any, default: nil
  attr :workflow_states, :list, default: []
  attr :sort_by, :string, default: "created_desc"
  attr :sidebar_project, :any, default: nil

  def toolbar(assigns) do
    ~H"""
    <%!-- Tasks: search + view toggle + state filter pills + sort --%>
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
    <%= if @sidebar_project do %>
      <div class="flex items-center bg-base-200/40 rounded-lg p-0.5">
        <span
          class="flex items-center gap-1 h-6 px-2 rounded-md text-[11px] font-medium bg-base-100 shadow-sm text-base-content cursor-default"
          title="List view"
        >
          <.icon name="hero-list-bullet-mini" class="w-3.5 h-3.5" /> List
        </span>
        <.link
          navigate={~p"/projects/#{@sidebar_project.id}/kanban"}
          class="flex items-center gap-1 h-6 px-2 rounded-md text-[11px] font-medium text-base-content/45 hover:text-base-content/70 transition-colors"
          title="Board view"
        >
          <.icon name="hero-view-columns-mini" class="w-3.5 h-3.5" /> Board
        </.link>
      </div>
    <% end %>
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
    <details
      id="tasks-sort-dropdown"
      phx-update="ignore"
      phx-hook="SortDropdown"
      data-label={case @sort_by do
        "created_asc" -> "Oldest"
        "priority" -> "Priority"
        _ -> "Newest"
      end}
      class="dropdown"
    >
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Sort: <span class="js-sort-label">{case @sort_by do
          "created_asc" -> "Oldest"
          "priority" -> "Priority"
          _ -> "Newest"
        end}</span> <.icon name="hero-chevron-down-mini" class="w-3 h-3 opacity-50" />
      </summary>
      <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[120px]">
        <%= for {value, label} <- [{"created_desc", "Newest"}, {"created_asc", "Oldest"}, {"priority", "Priority"}] do %>
          <li>
            <button
              phx-click="sort_by"
              phx-value-by={value}
              onclick="var d=this.closest('details');d.querySelector('.js-sort-label').textContent=this.textContent.trim();d.removeAttribute('open')"
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
end
