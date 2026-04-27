defmodule EyeInTheSkyWeb.TopBar.Notes do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  attr :search_query, :string, default: nil
  attr :sort_by, :string, default: "newest"
  attr :starred_filter, :boolean, default: false
  attr :type_filter, :string, default: "all"
  attr :new_href, :string, default: nil

  def toolbar(assigns) do
    ~H"""
    <%!-- Notes: search + quick note + starred + type + sort --%>
    <.search_bar
      id="notes-top-bar-search"
      size="xs"
      label="Search notes"
      placeholder="Search notes..."
      value={@search_query || ""}
      on_change="search"
      class="w-44"
    />
    <button
      phx-click="open_quick_note_modal"
      class="flex items-center gap-1 h-7 px-2.5 rounded-md text-mini font-medium text-base-content/60 hover:text-base-content hover:bg-base-content/8 transition-colors"
    >
      <.icon name="hero-bolt" class="size-3" /> Quick Note
    </button>
    <div class="w-px h-4 bg-base-content/10 mx-0.5" />
    <button
      phx-click="toggle_starred_filter"
      aria-label={if @starred_filter, do: "Remove starred filter", else: "Filter by starred"}
      class={"flex items-center gap-1 h-7 px-2 rounded-md text-mini font-medium transition-colors " <>
        if(@starred_filter,
          do: "bg-warning/10 text-warning",
          else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/8"
        )}
    >
      <.icon
        name={if @starred_filter, do: "hero-star-solid", else: "hero-star"}
        class="size-3.5"
      />
    </button>
    <.tab_pills value_key="type">
      <:item label="All" active={@type_filter == "all"} on_click="filter_type" value="all" />
      <:item label="Session" active={@type_filter == "session"} on_click="filter_type" value="session" />
      <:item label="Task" active={@type_filter == "task"} on_click="filter_type" value="task" />
    </.tab_pills>
    <details
      id="notes-sort-dropdown"
      phx-update="ignore"
      phx-hook="SortDropdown"
      data-label={if @sort_by == "oldest", do: "Oldest", else: "Newest"}
      class="dropdown"
    >
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-mini font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Sort: <span class="js-sort-label">{if @sort_by == "oldest", do: "Oldest", else: "Newest"}</span> <.icon name="hero-chevron-down-mini" class="size-3 opacity-50" />
      </summary>
      <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[120px]">
        <%= for {value, label} <- [{"newest", "Newest"}, {"oldest", "Oldest"}] do %>
          <li>
            <button
              phx-click="sort_notes"
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
    <%= if @new_href do %>
      <.link
        navigate={@new_href}
        class="ml-auto flex items-center gap-1 h-7 px-2.5 rounded-md text-mini font-medium bg-primary text-primary-content hover:bg-primary/90 transition-colors"
      >
        <.icon name="hero-plus" class="size-3" /> New Note
      </.link>
    <% end %>
    """
  end
end
