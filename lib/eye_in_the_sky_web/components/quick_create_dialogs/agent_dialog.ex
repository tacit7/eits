defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.AgentDialog do
  @moduledoc false
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents

  attr :project_id, :any, default: nil

  def quick_create_agent(assigns) do
    ~H"""
    <dialog
      id="quick-create-agent"
      phx-hook="QuickCreateAgent"
      data-project-id={@project_id}
      class="eits-modal   p-0 bg-transparent"
    >
      <div class="eits-dialog max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-message font-semibold text-base-content">New Agent</h2>
          <button
            data-qca-cancel
            type="button"
            class="eits-action eits-action--ghost eits-action--icon"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
          </button>
        </div>
        <form data-qca-form class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qca-instructions">Instructions</label>
            <textarea
              id="qca-instructions"
              data-qca-instructions
              required
              placeholder="What should this agent do?"
              rows="4"
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-message resize-none"
            ></textarea>
          </div>
          <div>
            <label class="sr-only" for="qca-parent-session">Parent Session UUID (optional)</label>
            <input
              id="qca-parent-session"
              data-qca-parent-session
              placeholder="Parent session UUID (optional)"
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-message min-h-[44px]"
            />
          </div>
          <div>
            <label class="sr-only" for="qca-model">Model</label>
            <select
              id="qca-model"
              data-qca-model
              class="select select-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-message min-h-[44px]"
            >
              <option value="haiku">Haiku (fast)</option>
              <option value="sonnet">Sonnet (balanced)</option>
            </select>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button
              data-qca-cancel
              type="button"
              class="eits-action eits-action--ghost eits-action--touch"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="eits-action eits-action--primary eits-action--touch"
            >
              Spawn Agent
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
