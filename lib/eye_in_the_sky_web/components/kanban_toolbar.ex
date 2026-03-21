defmodule EyeInTheSkyWeb.Components.KanbanToolbar do
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  attr :search_query, :string, required: true
  attr :show_completed, :boolean, required: true
  attr :bulk_mode, :boolean, required: true
  attr :active_filter_count, :integer, required: true

  def kanban_toolbar(assigns) do
    ~H"""
    <div class="mb-4 flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3 sticky top-0 z-10 bg-base-100 -mx-4 px-4 sm:-mx-6 sm:px-6 pt-1 pb-2 md:static md:mx-0 md:px-0 md:pt-0 md:pb-0 md:bg-transparent">
      <form phx-change="search" class="w-full sm:flex-1 sm:max-w-sm">
        <div class="relative">
          <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
            <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
          </div>
          <input
            type="text"
            name="query"
            value={@search_query}
            placeholder="Search tasks..."
            phx-debounce="300"
            class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-sm"
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
          class={"btn btn-sm sm:btn-xs gap-1 h-9 sm:h-7 min-h-0 " <> if(@show_completed, do: "btn-neutral", else: "btn-ghost border border-base-content/10")}
          title="Show completed tasks"
        >
          <.icon name="hero-check-circle-mini" class="w-3.5 h-3.5" />
          <span class="hidden sm:inline">Done</span>
        </button>
        <button
          phx-click="toggle_bulk_mode"
          class={"btn btn-sm sm:btn-xs gap-1 h-9 sm:h-7 min-h-0 " <> if(@bulk_mode, do: "btn-neutral", else: "btn-ghost border border-base-content/10")}
          title="Bulk select mode"
        >
          <.icon name="hero-check-mini" class="w-3.5 h-3.5" />
          <span class="hidden sm:inline">Select</span>
        </button>
        <button
          phx-click="toggle_filter_drawer"
          class={"btn btn-sm sm:btn-xs gap-1 h-9 sm:h-7 min-h-0 " <> if(@active_filter_count > 0, do: "btn-neutral", else: "btn-ghost border border-base-content/10")}
          title="Filter tasks"
        >
          <.icon name="hero-funnel-mini" class="w-3.5 h-3.5" />
          <span class="hidden sm:inline">Filter</span>
          <%= if @active_filter_count > 0 do %>
            <span class="badge badge-xs badge-primary">{@active_filter_count}</span>
          <% end %>
        </button>
        <button
          phx-click="toggle_new_task_drawer"
          class="btn btn-sm btn-primary gap-1.5 h-9 sm:h-7 min-h-0 text-xs"
        >
          <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Task
        </button>
      </div>
    </div>
    """
  end
end
