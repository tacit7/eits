defmodule EyeInTheSkyWeb.TopBar.Agents do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  attr :search_query, :string, default: ""
  attr :sort_by, :string, default: "name_asc"
  attr :scope_filter, :string, default: "all"

  def toolbar(assigns) do
    ~H"""
    <.search_bar
      id="agents-top-bar-search"
      size="xs"
      label="Search agents"
      placeholder="Search agents..."
      value={@search_query || ""}
      on_change="search"
      class="w-44"
      vim_search={true}
    />
    <div class="w-px h-4 bg-base-content/10 mx-0.5" />
    <details
      id="agents-scope-dropdown"
      phx-update="ignore"
      phx-hook="SortDropdown"
      data-label={scope_label(@scope_filter)}
      class="dropdown"
    >
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-mini font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Source: <span class="js-sort-label">{scope_label(@scope_filter)}</span>
        <.icon name="hero-chevron-down-mini" class="size-3 opacity-50" />
      </summary>
      <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[110px]">
        <%= for {value, label} <- scope_options() do %>
          <li>
            <button
              phx-click="filter_scope"
              phx-value-scope={value}
              onclick="var d=this.closest('details');d.querySelector('.js-sort-label').textContent=this.textContent.trim();d.removeAttribute('open')"
              class={"block w-full px-3 py-1.5 text-left text-mini rounded hover:bg-base-content/5 " <>
                if(@scope_filter == value, do: "text-base-content font-medium", else: "text-base-content/60")}
            >
              {label}
            </button>
          </li>
        <% end %>
      </ul>
    </details>
    <details
      id="agents-sort-dropdown"
      phx-update="ignore"
      phx-hook="SortDropdown"
      data-label={sort_label(@sort_by)}
      class="dropdown"
    >
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-mini font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Sort: <span class="js-sort-label">{sort_label(@sort_by)}</span>
        <.icon name="hero-chevron-down-mini" class="size-3 opacity-50" />
      </summary>
      <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[140px]">
        <%= for {value, label} <- sort_options() do %>
          <li>
            <button
              phx-click="sort_agents"
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

  defp scope_options do
    [{"all", "All"}, {"global", "Global"}, {"project", "Project"}]
  end

  defp sort_options do
    [
      {"name_asc", "Name A–Z"},
      {"name_desc", "Name Z–A"},
      {"recent", "Recent"},
      {"size_desc", "Largest"},
      {"size_asc", "Smallest"}
    ]
  end

  defp scope_label(v), do: Enum.find_value(scope_options(), "All", fn {k, l} -> k == v && l end)

  defp sort_label(v),
    do: Enum.find_value(sort_options(), "Name A–Z", fn {k, l} -> k == v && l end)
end
