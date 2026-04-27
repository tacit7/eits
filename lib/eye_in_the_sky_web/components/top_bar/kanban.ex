defmodule EyeInTheSkyWeb.TopBar.Kanban do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import EyeInTheSkyWeb.CoreComponents

  attr :search_query, :string, default: nil
  attr :show_completed, :boolean, default: false
  attr :bulk_mode, :boolean, default: false
  attr :active_filter_count, :integer, default: 0
  attr :sidebar_project, :any, default: nil

  def toolbar(assigns) do
    ~H"""
    <%= if @bulk_mode do %>
      <div class="flex-1" />
      <span class="text-[11px] text-base-content/50 font-medium">Selection mode</span>
      <button
        phx-click="toggle_bulk_mode"
        class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium text-base-content/45 hover:text-base-content/70 hover:bg-base-content/6 transition-colors"
      >
        Cancel
      </button>
    <% else %>
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
          class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium transition-colors text-base-content/45 hover:text-base-content/70 hover:bg-base-content/6"
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
    <% end %>
    """
  end
end
