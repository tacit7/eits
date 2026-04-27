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
    <.tab_pills value_key="filter">
      <:item label="All" active={@session_filter == "all"} on_click="filter_session" value="all" />
      <:item label="Active" active={@session_filter == "working"} on_click="filter_session" value="working"
             active_class="bg-base-100 text-success shadow-sm" />
      <:item label="Archived" active={@session_filter == "archived"} on_click="filter_session" value="archived"
             active_class="bg-base-100 text-warning shadow-sm" />
    </.tab_pills>
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
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-mini font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Sort: <span class="js-sort-label">{case @sort_by do
          "name" -> "Name"
          "agent" -> "Agent"
          "model" -> "Model"
          _ -> "Last msg"
        end}</span> <.icon name="hero-chevron-down-mini" class="size-3 opacity-50" />
      </summary>
      <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[120px]">
        <%= for {value, label} <- [{"last_message", "Last msg"}, {"name", "Name"}, {"agent", "Agent"}, {"model", "Model"}] do %>
          <li>
            <button
              phx-click="sort"
              phx-value-by={value}
              onclick="var d=this.closest('details');d.querySelector('.js-sort-label').textContent=this.textContent.trim();d.removeAttribute('open')"
              class={"block w-full px-3 py-1.5 text-left text-mini rounded hover:bg-base-content/5 " <>
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
