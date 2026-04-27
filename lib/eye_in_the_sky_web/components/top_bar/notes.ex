defmodule EyeInTheSkyWeb.TopBar.Notes do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  attr :search_query, :string, default: nil
  attr :notes_sort_by, :string, default: "newest"
  attr :notes_starred_filter, :boolean, default: false
  attr :notes_type_filter, :string, default: "all"
  attr :notes_new_href, :string, default: nil

  def toolbar(assigns) do
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
    <div class="flex items-center gap-0.5 bg-base-200/40 rounded-lg p-0.5">
      <%= for {value, label} <- [{"all", "All"}, {"session", "Session"}, {"task", "Task"}] do %>
        <button
          phx-click="filter_type"
          phx-value-value={value}
          class={"px-2.5 py-1 rounded-md text-[11px] font-medium transition-all duration-150 " <>
            if(@notes_type_filter == value,
              do: "bg-base-100 text-base-content shadow-sm",
              else: "text-base-content/45 hover:text-base-content/70"
            )}
        >
          {label}
        </button>
      <% end %>
    </div>
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
end
