defmodule EyeInTheSkyWeb.Components.FilterSheet do
  @moduledoc false
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents, only: [icon: 1]

  @doc """
  A mobile bottom-sheet for filtering and sorting task lists.

  Events emitted (hardcoded, parent LiveView must handle):
  - `close_filter_sheet` — close button, backdrop click, Escape key
  - `filter_status` with `state_id` — status filter button clicks (empty string for "all")
  - `sort_by` with `value` — sort button clicks (only when show_sort is true)
  """
  attr :id, :string, required: true
  attr :show, :boolean, required: true
  attr :title, :string, default: "Filter & Sort"
  attr :workflow_states, :list, required: true
  attr :filter_state_id, :any, default: nil
  attr :show_sort, :boolean, default: false
  attr :sort_by, :string, default: "created_desc"

  def filter_sheet(assigns) do
    ~H"""
    <%= if @show do %>
      <div
        class="fixed inset-0 z-40 bg-black/40"
        phx-click="close_filter_sheet"
        aria-hidden="true"
      >
      </div>
      <div
        class="fixed inset-x-0 bottom-0 z-50 rounded-t-2xl bg-base-100 shadow-xl safe-bottom-sheet"
        role="dialog"
        aria-modal="true"
        aria-label="Filter tasks"
        id={@id}
        phx-window-keydown="close_filter_sheet"
        phx-key="Escape"
      >
        <div class="flex justify-center pt-3 pb-1">
          <div class="w-10 h-1 rounded-full bg-base-content/20"></div>
        </div>
        <div class="px-5 pb-6 pt-2">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-sm font-semibold">{@title}</h2>
            <button
              phx-click="close_filter_sheet"
              class="btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px]"
              aria-label="Close filter panel"
            >
              <.icon name="hero-x-mark-mini" class="w-4 h-4" />
            </button>
          </div>

          <fieldset class={if @show_sort, do: "mb-5", else: "mb-6"}>
            <legend class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-2">
              Status
            </legend>
            <div class="flex flex-wrap gap-2">
              <button
                phx-click="filter_status"
                phx-value-state_id=""
                aria-pressed={is_nil(@filter_state_id)}
                class={"btn btn-sm " <>
                  if(is_nil(@filter_state_id),
                    do: "btn-primary",
                    else: "btn-ghost border border-base-content/15"
                  )}
              >
                All
              </button>
              <button
                :for={state <- @workflow_states}
                phx-click="filter_status"
                phx-value-state_id={state.id}
                aria-pressed={@filter_state_id == state.id}
                class={"btn btn-sm " <>
                  if(@filter_state_id == state.id,
                    do: "btn-primary",
                    else: "btn-ghost border border-base-content/15"
                  )}
              >
                {state.name}
              </button>
            </div>
          </fieldset>

          <fieldset :if={@show_sort} class="mb-6">
            <legend class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-2">
              Sort by
            </legend>
            <div class="flex flex-wrap gap-2">
              <button
                :for={
                  {label, val} <- [
                    {"Newest", "created_desc"},
                    {"Oldest", "created_asc"},
                    {"Priority", "priority"}
                  ]
                }
                phx-click="sort_by"
                phx-value-by={val}
                aria-pressed={@sort_by == val}
                class={"btn btn-sm " <>
                  if(@sort_by == val,
                    do: "btn-primary",
                    else: "btn-ghost border border-base-content/15"
                  )}
              >
                {label}
              </button>
            </div>
          </fieldset>

          <div class="flex gap-3">
            <button phx-click="close_filter_sheet" class="btn btn-primary flex-1">
              Apply
            </button>
            <button
              phx-click="filter_status"
              phx-value-state_id=""
              class="btn btn-ghost"
              aria-label="Reset filters"
            >
              Reset
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
