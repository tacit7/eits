defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.ChatDialog do
  @moduledoc false
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents

  attr :project_id, :any, default: nil

  def quick_create_chat(assigns) do
    ~H"""
    <dialog
      id="quick-create-chat"
      phx-hook="QuickCreateChat"
      data-project-id={@project_id}
      class="eits-modal   p-0 bg-transparent"
    >
      <div class="eits-dialog max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-message font-semibold text-base-content">New Chat</h2>
          <button
            data-qcc-cancel
            type="button"
            class="eits-action eits-action--ghost eits-action--icon"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
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
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-message min-h-[44px]"
              autocomplete="off"
            />
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button
              data-qcc-cancel
              type="button"
              class="eits-action eits-action--ghost eits-action--touch"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="eits-action eits-action--primary eits-action--touch"
            >
              Start Chat
            </button>
          </div>
        </form>
      </div>
      <form method="dialog" class="eits-modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end
end
