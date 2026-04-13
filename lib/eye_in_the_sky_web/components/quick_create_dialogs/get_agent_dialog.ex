defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.GetAgentDialog do
  @moduledoc false
  use Phoenix.Component

  def quick_get_agent(assigns) do
    ~H"""
    <dialog
      id="quick-get-agent"
      phx-hook="QuickGetAgent"
      class="modal modal-bottom sm:modal-middle p-0 bg-transparent"
    >
      <div class="modal-box max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-base-content">Get Agent Details</h2>
          <button
            data-qga-cancel
            type="button"
            class="btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px]"
            aria-label="Close"
          >
            <span class="hero-x-mark w-4 h-4"></span>
          </button>
        </div>
        <form data-qga-form class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qga-agent-uuid">Agent UUID</label>
            <input
              id="qga-agent-uuid"
              data-qga-agent-uuid
              required
              placeholder="Enter agent UUID"
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base min-h-[44px]"
            />
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qga-cancel type="button" class="btn btn-ghost btn-sm min-h-[44px]">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm min-h-[44px]">Get Details</button>
          </div>
        </form>
        <div data-qga-result class="hidden p-4 border-t border-base-content/10">
          <div class="space-y-2 text-sm">
            <div><strong>UUID:</strong> <span data-qga-result-uuid></span></div>
            <div><strong>Name:</strong> <span data-qga-result-name></span></div>
            <div><strong>Status:</strong> <span data-qga-result-status></span></div>
            <div><strong>Sessions:</strong> <span data-qga-result-sessions></span></div>
            <div data-qga-result-instructions-container class="hidden">
              <strong>Instructions:</strong>
              <pre
                class="mt-1 p-2 bg-base-200 rounded text-xs whitespace-pre-wrap"
                data-qga-result-instructions
              ></pre>
            </div>
            <div data-qga-result-project-container class="hidden">
              <strong>Project:</strong> <span data-qga-result-project></span>
            </div>
            <div data-qga-result-created-container class="hidden">
              <strong>Created:</strong> <span data-qga-result-created></span>
            </div>
          </div>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end
end
