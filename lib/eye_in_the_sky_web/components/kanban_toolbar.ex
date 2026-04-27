defmodule EyeInTheSkyWeb.Components.KanbanToolbar do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import EyeInTheSkyWeb.CoreComponents

  attr :project_id, :any, required: true
  attr :search_query, :string, required: true
  attr :show_completed, :boolean, required: true
  attr :bulk_mode, :boolean, required: true
  attr :active_filter_count, :integer, required: true

  def kanban_toolbar(assigns) do
    ~H"""
    <div class="mb-4 flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3 sticky top-[calc(3rem+env(safe-area-inset-top))] md:top-0 z-10 bg-base-100 -mx-4 px-4 sm:-mx-6 sm:px-6 pt-1 pb-2 md:static md:mx-0 md:px-0 md:pt-0 md:pb-0 md:bg-transparent">
      <form phx-change="search" class="w-full sm:flex-1 sm:max-w-sm">
        <div class="relative">
          <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
            <.icon name="hero-magnifying-glass-mini" class="size-4 text-base-content/25" />
          </div>
          <input
            type="text"
            name="query"
            value={@search_query}
            placeholder="Search tasks..."
            phx-debounce="300"
            class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-base min-h-[44px]"
            autocomplete="off"
          />
        </div>
        <%= if String.length(String.trim(@search_query)) == 1 do %>
          <p class="text-xs text-base-content/30 mt-1 pl-9">Type at least 2 characters to search</p>
        <% end %>
      </form>

      <div class="flex items-center gap-1.5">
        <button
          phx-click="toggle_show_completed"
          class={"btn btn-sm sm:btn-xs gap-1 h-11 sm:h-7 min-h-0 " <> if(@show_completed, do: "btn-neutral", else: "btn-ghost border border-base-content/10")}
          title="Show completed tasks"
        >
          <.icon name="hero-check-circle-mini" class="size-3.5" />
          <span class="hidden sm:inline">Done</span>
        </button>
        <button
          phx-click="toggle_bulk_mode"
          class={"btn btn-sm sm:btn-xs gap-1 h-11 sm:h-7 min-h-0 " <> if(@bulk_mode, do: "btn-neutral", else: "btn-ghost border border-base-content/10")}
          title="Bulk select mode"
        >
          <.icon name="hero-check-mini" class="size-3.5" />
          <span class="hidden sm:inline">Select</span>
        </button>
        <button
          phx-click="toggle_filter_drawer"
          class={"btn btn-sm sm:btn-xs gap-1 h-11 sm:h-7 min-h-0 " <> if(@active_filter_count > 0, do: "btn-neutral", else: "btn-ghost border border-base-content/10")}
          title="Filter tasks"
        >
          <.icon name="hero-funnel-mini" class="size-3.5" />
          <span class="hidden sm:inline">Filter</span>
          <%= if @active_filter_count > 0 do %>
            <span class="badge badge-xs badge-primary">{@active_filter_count}</span>
          <% end %>
        </button>
        <.link
          navigate={~p"/projects/#{@project_id}/tasks"}
          class="btn btn-sm sm:btn-xs btn-ghost border border-base-content/10 gap-1 h-11 sm:h-7 min-h-0"
          title="List view"
        >
          <.icon name="hero-list-bullet-mini" class="size-3.5" />
          <span class="hidden sm:inline">List</span>
        </.link>
        <button
          phx-click="toggle_new_task_drawer"
          class="btn btn-sm btn-primary gap-1.5 h-11 sm:h-7 min-h-0 text-xs"
        >
          <.icon name="hero-plus-mini" class="size-3.5" /> New Task
        </button>
      </div>
    </div>
    """
  end
end
