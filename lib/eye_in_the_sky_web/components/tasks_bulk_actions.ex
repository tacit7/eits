defmodule EyeInTheSkyWeb.Components.TasksBulkActions do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  attr :task_count, :integer, required: true
  attr :tasks_select_mode, :boolean, required: true
  attr :selected_task_ids, :any, required: true
  attr :workflow_states, :list, required: true

  def bulk_select_toolbar(assigns) do
    ~H"""
    <%= if @tasks_select_mode do %>
      <div class="mb-3 flex items-center gap-3 px-2 py-1.5">
        <div phx-click="toggle_select_all_tasks" class="cursor-pointer">
          <.square_checkbox
            checked={MapSet.size(@selected_task_ids) == @task_count}
            indeterminate={
              MapSet.size(@selected_task_ids) > 0 &&
                MapSet.size(@selected_task_ids) < @task_count
            }
            aria-label="Select all tasks"
          />
        </div>
        <%= if MapSet.size(@selected_task_ids) > 0 do %>
          <span class="text-mini text-base-content/50 font-medium">
            {MapSet.size(@selected_task_ids)} selected
          </span>
          <details
            id="tasks-bulk-state-dropdown"
            phx-update="ignore"
            class="dropdown"
          >
            <summary class="btn btn-ghost btn-xs gap-1 min-h-[44px] text-base-content/70 hover:text-base-content [list-style:none] [&::-webkit-details-marker]:hidden">
              <.icon name="hero-arrows-right-left-mini" class="size-3.5" /> Move to
              <.icon
                name="hero-chevron-down-mini"
                class="size-3 opacity-50"
              />
            </summary>
            <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[140px]">
              <%= for state <- @workflow_states do %>
                <li>
                  <button
                    phx-click="bulk_set_state"
                    phx-value-state_id={state.id}
                    onclick="this.closest('details').removeAttribute('open')"
                    class="flex items-center gap-2 w-full px-3 py-1.5 text-left text-mini rounded hover:bg-base-content/5 text-base-content/70 hover:text-base-content"
                  >
                    <span
                      class="inline-block w-2 h-2 rounded-full flex-shrink-0"
                      style={"background-color: #{state.color}"}
                      aria-hidden="true"
                    />
                    {state.name}
                  </button>
                </li>
              <% end %>
            </ul>
          </details>
          <button
            phx-click="confirm_archive_selected_tasks"
            class="btn btn-ghost btn-xs text-warning/70 hover:text-warning hover:bg-warning/10 gap-1 min-h-[44px] min-w-[44px]"
          >
            <.icon name="hero-archive-box-mini" class="size-3.5" /> Archive
          </button>
          <button
            phx-click="delete_selected_tasks"
            data-confirm={"Delete #{MapSet.size(@selected_task_ids)} task#{if MapSet.size(@selected_task_ids) != 1, do: "s"}?"}
            class="btn btn-ghost btn-xs text-error/70 hover:text-error hover:bg-error/10 gap-1 min-h-[44px] min-w-[44px]"
          >
            <.icon name="hero-trash-mini" class="size-3.5" /> Delete
          </button>
        <% else %>
          <span class="text-mini text-base-content/30">{@task_count} tasks</span>
        <% end %>
        <button
          phx-click="exit_select_mode_tasks"
          class="ml-auto btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px] text-base-content/40 hover:text-base-content/70"
          aria-label="Exit select mode"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    <% end %>
    """
  end

  attr :show, :boolean, required: true
  attr :selected_task_ids, :any, required: true

  def archive_confirm_modal(assigns) do
    ~H"""
    <dialog
      id="tasks-archive-confirm-modal"
      class={"modal modal-bottom sm:modal-middle " <> if(@show, do: "modal-open", else: "")}
    >
      <div class="modal-box w-full sm:max-w-sm pb-[env(safe-area-inset-bottom)]">
        <h3 class="text-lg font-bold">Archive tasks</h3>
        <p class="py-4 text-sm text-base-content/70">
          <% count = MapSet.size(@selected_task_ids) %> Archive {count} selected task{if count == 1,
            do: "",
            else: "s"}?
          Archived tasks can be unarchived later.
        </p>
        <div class="modal-action">
          <button phx-click="cancel_archive_selected_tasks" class="btn btn-sm btn-ghost min-h-[44px]">
            Cancel
          </button>
          <button phx-click="archive_selected_tasks" class="btn btn-sm btn-warning min-h-[44px]">
            Archive
          </button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel_archive_selected_tasks">close</button>
      </form>
    </dialog>
    """
  end
end
