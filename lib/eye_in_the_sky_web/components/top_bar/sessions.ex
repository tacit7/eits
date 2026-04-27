defmodule EyeInTheSkyWeb.TopBar.Sessions do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import EyeInTheSkyWeb.CoreComponents

  attr :search_query, :string, default: nil
  attr :session_filter, :string, default: "all"
  attr :sort_by, :string, default: "last_message"

  def toolbar(assigns) do
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
      <%= for {value, label} <- [{"all", "All"}, {"working", "Active"}, {"archived", "Archived"}] do %>
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
    <details id="sessions-sort-dropdown" class="dropdown">
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Sort: {case @sort_by do
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
end
