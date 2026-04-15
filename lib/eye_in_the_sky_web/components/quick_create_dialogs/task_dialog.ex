defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.TaskDialog do
  @moduledoc false
  use Phoenix.Component

  attr :project_id, :any, default: nil

  def quick_create_task(assigns) do
    ~H"""
    <dialog
      id="quick-create-task"
      phx-hook="QuickCreateTask"
      data-project-id={@project_id}
      class="modal modal-bottom sm:modal-middle p-0 bg-transparent"
    >
      <div class="modal-box max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-base-content">New Task</h2>
          <button
            data-qct-cancel
            type="button"
            class="btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px]"
            aria-label="Close"
          >
            <span class="hero-x-mark w-4 h-4"></span>
          </button>
        </div>
        <form data-qct-form class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qct-title">Title</label>
            <input
              id="qct-title"
              type="text"
              data-qct-title
              required
              placeholder="Task title..."
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base min-h-[44px]"
              autocomplete="off"
            />
          </div>
          <div>
            <label class="sr-only" for="qct-description">Description</label>
            <textarea
              id="qct-description"
              data-qct-description
              placeholder="Description (optional)..."
              rows="3"
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base resize-none"
            ></textarea>
          </div>
          <div>
            <label class="sr-only" for="qct-tags">Tags</label>
            <input
              id="qct-tags"
              type="text"
              data-qct-tags
              placeholder="tag1, tag2, tag3"
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base min-h-[44px]"
              autocomplete="off"
            />
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qct-cancel type="button" class="btn btn-ghost btn-sm min-h-[44px]">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary btn-sm min-h-[44px]">Create Task</button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end
end
