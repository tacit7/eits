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
    <%!-- Sessions: search + filter tabs + sort --%>
    <.search_bar
      id="top-bar-search"
      size="xs"
      label="Search sessions"
      placeholder="Search..."
      value={@search_query || ""}
      on_change="search"
      class="flex-1 max-w-xs"
    />
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
    <details
      id="sessions-sort-dropdown"
      phx-update="ignore"
      phx-hook="SortDropdown"
      data-label={case @sort_by do
        "name" -> "Name"
        "agent" -> "Agent"
        "model" -> "Model"
        _ -> "Last msg"
      end}
      class="dropdown"
    >
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Sort: <span class="js-sort-label">{case @sort_by do
          "name" -> "Name"
          "agent" -> "Agent"
          "model" -> "Model"
          _ -> "Last msg"
        end}</span> <.icon name="hero-chevron-down-mini" class="w-3 h-3 opacity-50" />
      </summary>
      <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[120px]">
        <%= for {value, label} <- [{"last_message", "Last msg"}, {"name", "Name"}, {"agent", "Agent"}, {"model", "Model"}] do %>
          <li>
            <button
              phx-click="sort"
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
