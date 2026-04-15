defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.NoteDialog do
  @moduledoc false
  use Phoenix.Component

  def quick_create_note(assigns) do
    ~H"""
    <dialog
      id="quick-create-note"
      phx-hook="QuickCreateNote"
      class="modal modal-bottom sm:modal-middle p-0 bg-transparent"
    >
      <div class="modal-box max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-base-content">New Note</h2>
          <button
            data-qcn-cancel
            type="button"
            class="btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px]"
            aria-label="Close"
          >
            <span class="hero-x-mark w-4 h-4"></span>
          </button>
        </div>
        <form data-qcn-form class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qcn-title">Title</label>
            <input
              id="qcn-title"
              type="text"
              data-qcn-title
              required
              placeholder="Note title..."
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base min-h-[44px]"
              autocomplete="off"
            />
          </div>
          <div>
            <label class="sr-only" for="qcn-body">Body</label>
            <textarea
              id="qcn-body"
              data-qcn-body
              placeholder="Note content..."
              rows="4"
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base resize-none"
            ></textarea>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qcn-cancel type="button" class="btn btn-ghost btn-sm min-h-[44px]">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary btn-sm min-h-[44px]">Create Note</button>
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
