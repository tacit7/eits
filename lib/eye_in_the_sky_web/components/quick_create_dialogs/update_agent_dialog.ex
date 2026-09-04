defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.UpdateAgentDialog do
  @moduledoc false
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents

  def quick_update_agent(assigns) do
    ~H"""
    <dialog
      id="quick-update-agent"
      phx-hook="QuickUpdateAgent"
      class="eits-modal   p-0 bg-transparent"
    >
      <div class="eits-dialog max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-message font-semibold text-base-content">Update Agent Instructions</h2>
          <button
            data-qua-cancel
            type="button"
            class="eits-action eits-action--ghost eits-action--icon"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
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
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-message min-h-[44px]"
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
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-message resize-none"
            ></textarea>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button
              data-qua-cancel
              type="button"
              class="eits-action eits-action--ghost eits-action--touch"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="eits-action eits-action--primary eits-action--touch"
            >
              Update Agent
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
