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
          <h2 class="text-message font-semibold text-base-content">Delete Agent</h2>
          <button
            data-qda-cancel
            type="button"
            class="focus-ring inline-flex min-h-[44px] min-w-[44px] items-center justify-center rounded-box text-base-content/45 transition-colors hover:bg-base-content/5 hover:text-base-content/70"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
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
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-message min-h-[44px]"
            />
          </div>
          <div class="alert alert-warning text-message">
            <.icon name="hero-exclamation-triangle" class="shrink-0 size-5" />
            <span>Warning: This action cannot be undone. The agent will be permanently deleted.</span>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button
              data-qda-cancel
              type="button"
              class="focus-ring inline-flex min-h-[44px] items-center justify-center rounded-box px-3 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="focus-ring inline-flex min-h-[44px] items-center justify-center rounded-box bg-error px-3 text-mini font-medium text-error-content transition-colors hover:bg-error/85"
            >
              Delete Agent
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
