defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.NoteDialog do
  @moduledoc false
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents

  attr :project_id, :any, default: nil

  def quick_create_note(assigns) do
    ~H"""
    <dialog
      id="quick-create-note"
      phx-hook="QuickCreateNote"
      data-project-id={@project_id}
      class="modal modal-bottom sm:modal-middle p-0 bg-transparent"
    >
      <div class="modal-box max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-message font-semibold text-base-content">New Note</h2>
          <button
            data-qcn-cancel
            type="button"
            class="eits-action eits-action--ghost eits-action--icon"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
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
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-message min-h-[44px]"
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
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-message resize-none"
            ></textarea>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button
              data-qcn-cancel
              type="button"
              class="eits-action eits-action--ghost eits-action--touch"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="eits-action eits-action--primary eits-action--touch"
            >
              Create Note
            </button>
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
