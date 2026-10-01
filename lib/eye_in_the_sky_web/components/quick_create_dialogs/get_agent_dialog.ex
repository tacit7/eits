defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.GetAgentDialog do
  @moduledoc false
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents

  def quick_get_agent(assigns) do
    ~H"""
    <dialog
      id="quick-get-agent"
      phx-hook="QuickGetAgent"
      class="eits-modal   p-0 bg-transparent"
    >
      <div class="eits-dialog max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-message font-semibold text-base-content">Get Agent Details</h2>
          <button
            data-qga-cancel
            type="button"
            class="eits-action eits-action--ghost eits-action--icon"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
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
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-message min-h-[44px]"
            />
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button
              data-qga-cancel
              type="button"
              class="eits-action eits-action--ghost eits-action--touch"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="eits-action eits-action--primary eits-action--touch"
            >
              Get Details
            </button>
          </div>
        </form>
        <div data-qga-result class="hidden p-4 border-t border-base-content/10">
          <div class="space-y-2 text-message">
            <div><strong>UUID:</strong> <span data-qga-result-uuid></span></div>
            <div><strong>Name:</strong> <span data-qga-result-name></span></div>
            <div><strong>Status:</strong> <span data-qga-result-status></span></div>
            <div><strong>Sessions:</strong> <span data-qga-result-sessions></span></div>
            <div data-qga-result-instructions-container class="hidden">
              <strong>Instructions:</strong>
              <pre
                class="mt-1 p-2 bg-base-200 rounded-box text-mini whitespace-pre-wrap"
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
      <form method="dialog" class="eits-modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end
end
