defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.DeleteAgentDialog do
  @moduledoc false
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents

  def quick_delete_agent(assigns) do
    ~H"""
    <dialog
      id="quick-delete-agent"
      phx-hook="QuickDeleteAgent"
      class="modal modal-bottom sm:modal-middle p-0 bg-transparent"
    >
      <div class="modal-box max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-base-content">Delete Agent</h2>
          <button
            data-qda-cancel
            type="button"
            class="btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px]"
            aria-label="Close"
          >
            <span class="hero-x-mark w-4 h-4"></span>
          </button>
        </div>
        <form data-qda-form class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qda-agent-uuid">Agent UUID</label>
            <input
              id="qda-agent-uuid"
              data-qda-agent-uuid
              required
              placeholder="Enter agent UUID to delete"
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base min-h-[44px]"
            />
          </div>
          <div class="alert alert-warning text-sm">
            <.icon name="hero-exclamation-triangle" class="shrink-0 h-5 w-5" />
            <span>Warning: This action cannot be undone. The agent will be permanently deleted.</span>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qda-cancel type="button" class="btn btn-ghost btn-sm min-h-[44px]">
              Cancel
            </button>
            <button type="submit" class="btn btn-error btn-sm min-h-[44px]">Delete Agent</button>
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
