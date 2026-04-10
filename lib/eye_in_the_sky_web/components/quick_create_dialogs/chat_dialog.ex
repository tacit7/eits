defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.ChatDialog do
  @moduledoc false
  use Phoenix.Component

  attr :project_id, :any, default: nil

  def quick_create_chat(assigns) do
    ~H"""
    <dialog
      id="quick-create-chat"
      phx-hook="QuickCreateChat"
      data-project-id={@project_id}
      class="modal modal-bottom sm:modal-middle p-0 bg-transparent"
    >
      <div class="modal-box max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-base-content">New Chat</h2>
          <button
            data-qcc-cancel
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            aria-label="Close"
          >
            <span class="hero-x-mark w-4 h-4"></span>
          </button>
        </div>
        <form data-qcc-form class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qcc-name">Name</label>
            <input
              id="qcc-name"
              type="text"
              data-qcc-name
              placeholder="Session name (optional)..."
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base"
              autocomplete="off"
            />
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qcc-cancel type="button" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm">Start Chat</button>
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
