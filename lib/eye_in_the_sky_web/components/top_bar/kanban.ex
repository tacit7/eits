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
  attr :selected_tasks, :any, default: nil

  def toolbar(assigns) do
    assigns =
      assign(assigns, :selected_count, selected_count(assigns[:selected_tasks]))

    ~H"""
    <%= if @bulk_mode do %>
      <span class="text-[11px] font-medium text-base-content">
        {@selected_count} selected
      </span>
      <span class="w-px h-4 bg-base-content/10 mx-0.5" />
      <button
        phx-click="bulk_move"
        phx-value-state_id="3"
        class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium bg-success/15 text-success hover:bg-success/25 transition-colors"
        title="Mark selected tasks done"
      >
        <.icon name="hero-check-circle-mini" class="size-3.5" /> Done
      </button>
      <button
        phx-click="clear_selection"
        class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium text-base-content/45 hover:text-base-content/70 hover:bg-base-content/6 transition-colors"
        title="Clear selection"
      >
        <.icon name="hero-x-mark-mini" class="size-3.5" /> Clear
      </button>
      <button
        phx-click="bulk_delete"
        phx-confirm="Delete selected tasks?"
        class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium text-error hover:bg-error/10 transition-colors"
        title="Delete selected tasks"
      >
        <.icon name="hero-trash-mini" class="size-3.5" /> Delete
      </button>
      <div class="flex-1" />
      <button
        phx-click="toggle_bulk_mode"
        class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium text-base-content/45 hover:text-base-content/70 hover:bg-base-content/6 transition-colors"
      >
        Cancel
      </button>
    <% else %>
      <.search_bar
        id="top-bar-kanban-search"
        size="xs"
        label="Search tasks"
        placeholder="Search tasks..."
        value={@search_query || ""}
        on_change="search"
        class="flex-1 max-w-xs"
      />
      <%= if @sidebar_project do %>
        <div class="flex items-center bg-base-200/40 rounded-lg p-0.5">
          <.link
            navigate={~p"/projects/#{@sidebar_project.id}/tasks"}
            class="flex items-center gap-1 h-6 px-2 rounded-md text-[11px] font-medium text-base-content/45 hover:text-base-content/70 transition-colors"
            title="List view"
          >
            <.icon name="hero-list-bullet-mini" class="size-3.5" /> List
          </.link>
          <span
            class="flex items-center gap-1 h-6 px-2 rounded-md text-[11px] font-medium bg-base-100 shadow-sm text-base-content cursor-default"
            title="Board view"
          >
            <.icon name="hero-view-columns-mini" class="size-3.5" /> Board
          </span>
        </div>
      <% end %>
      <div class="flex items-center gap-1">
        <button
          phx-click="toggle_bulk_mode"
          class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium text-base-content/45 hover:text-base-content/70 hover:bg-base-content/6 transition-colors"
          title="Select tasks"
        >
          <.icon name="hero-check-mini" class="size-3.5" /> Select
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
          <.icon name="hero-funnel-mini" class="size-3.5" />
          Filters
          <%= if @active_filter_count && @active_filter_count > 0 do %>
            <span class="inline-flex items-center justify-center size-4 rounded-full bg-primary text-primary-content text-[9px] font-bold">
              {@active_filter_count}
            </span>
          <% end %>
        </button>
      </div>
    <% end %>
    """
  end

  defp selected_count(nil), do: 0
  defp selected_count(%MapSet{} = set), do: MapSet.size(set)
  defp selected_count(_), do: 0
end
