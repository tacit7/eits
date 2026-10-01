defmodule EyeInTheSkyWeb.Components.KanbanBulkBar do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.Live.Shared.KanbanFilters, only: [state_dot_color: 1]

  attr :bulk_mode, :boolean, required: true
  attr :selected_tasks, :any, required: true
  attr :workflow_states, :list, required: true

  def kanban_bulk_bar(assigns) do
    ~H"""
    <%= if @bulk_mode do %>
      <div class="mb-2 flex flex-wrap items-center gap-1.5 sm:gap-2 px-2 py-1.5 rounded-box bg-primary/10 border border-primary/20">
        <span class="text-mini font-medium text-primary">
          {MapSet.size(@selected_tasks)} selected
        </span>
        <%= if MapSet.size(@selected_tasks) > 0 do %>
          <span class="text-base-content/15 hidden sm:inline">|</span>
          <span class="text-mini text-base-content/40 hidden sm:inline">Move to:</span>
          <%= for state <- @workflow_states do %>
            <button
              phx-click="bulk_move"
              phx-value-state_id={state.id}
              class="focus-ring inline-flex min-h-[44px] items-center gap-1 rounded-box px-2 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content/80 sm:h-7 sm:min-h-0"
            >
              <span
                class="w-1.5 h-1.5 rounded-full"
                style={"background-color: #{state_dot_color(state.color)}"}
              >
              </span>
              {state.name}
            </button>
          <% end %>
          <span class="text-base-content/15 hidden sm:inline">|</span>
          <button
            phx-click="bulk_archive"
            class="focus-ring inline-flex min-h-[44px] items-center gap-1 rounded-box px-2 text-mini font-medium text-warning transition-colors hover:bg-warning/10 sm:h-7 sm:min-h-0"
          >
            <.icon name="hero-archive-box-mini" class="size-3" />
            <span>Archive</span>
          </button>
          <button
            phx-click="bulk_delete"
            phx-confirm={"Delete #{MapSet.size(@selected_tasks)} tasks?"}
            class="focus-ring inline-flex min-h-[44px] items-center gap-1 rounded-box px-2 text-mini font-medium text-error transition-colors hover:bg-error/10 sm:h-7 sm:min-h-0"
          >
            <.icon name="hero-trash-mini" class="size-3" />
            <span>Delete</span>
          </button>
        <% end %>
        <div class="flex-1" />
        <button
          phx-click="toggle_bulk_mode"
          class="focus-ring inline-flex min-h-[44px] items-center gap-1 rounded-box px-2 text-mini font-medium text-base-content/50 transition-colors hover:bg-base-content/5 hover:text-base-content/75 sm:h-7 sm:min-h-0"
        >
          <.icon name="hero-x-mark-mini" class="size-3" />
          <span>Cancel</span>
        </button>
      </div>
    <% end %>
    """
  end
end
