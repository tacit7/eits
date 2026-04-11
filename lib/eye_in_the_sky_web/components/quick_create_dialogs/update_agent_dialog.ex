defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.UpdateAgentDialog do
  @moduledoc false
  use Phoenix.Component

  def quick_update_agent(assigns) do
    ~H"""
    <dialog
      id="quick-update-agent"
      phx-hook="QuickUpdateAgent"
      class="modal modal-bottom sm:modal-middle p-0 bg-transparent"
    >
      <div class="modal-box max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-base-content">Update Agent Instructions</h2>
          <button
            data-qua-cancel
            type="button"
            class="btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px]"
            aria-label="Close"
          >
            <span class="hero-x-mark w-4 h-4"></span>
          </button>
        </div>
        <form data-qua-form class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qua-agent-uuid">Agent UUID</label>
            <input
              id="qua-agent-uuid"
              data-qua-agent-uuid
              required
              placeholder="Agent UUID"
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base"
            />
          </div>
          <div>
            <label class="sr-only" for="qua-instructions">Instructions</label>
            <textarea
              id="qua-instructions"
              data-qua-instructions
              required
              placeholder="Updated instructions for the agent"
              rows="4"
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base resize-none"
            ></textarea>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qua-cancel type="button" class="btn btn-ghost btn-sm min-h-[44px]">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm min-h-[44px]">Update Agent</button>
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
