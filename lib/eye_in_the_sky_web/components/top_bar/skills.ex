defmodule EyeInTheSkyWeb.TopBar.Skills do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  attr :search_query, :string, default: ""
  attr :sort_by, :string, default: "name_asc"
  attr :source_filter, :string, default: "all"

  def toolbar(assigns) do
    ~H"""
    <.search_bar
      id="skills-top-bar-search"
      size="xs"
      label="Search skills"
      placeholder="Search skills..."
      value={@search_query || ""}
      on_change="search"
      class="w-44"
    />
    <div class="w-px h-4 bg-base-content/10 mx-0.5" />
    <.tab_pills value_key="filter">
      <:item label="All" active={@source_filter == "all"} on_click="filter_source" value="all" />
      <:item label="Skills" active={@source_filter == "skills"} on_click="filter_source" value="skills" />
      <:item label="Commands" active={@source_filter == "commands"} on_click="filter_source" value="commands" />
      <:item label="Project" active={@source_filter == "project"} on_click="filter_source" value="project" />
    </.tab_pills>
    <details
      id="skills-sort-dropdown"
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
              phx-click="sort_skills"
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

  defp sort_options do
    [
      {"name_asc", "Name A–Z"},
      {"name_desc", "Name Z–A"},
      {"recent", "Recent"},
      {"size_desc", "Largest"},
      {"size_asc", "Smallest"}
    ]
  end

  defp sort_label(sort_by) do
    sort_options()
    |> Enum.find(fn {v, _} -> v == sort_by end)
    |> case do
      nil -> "Name A–Z"
      {_, label} -> label
    end
  end
end
