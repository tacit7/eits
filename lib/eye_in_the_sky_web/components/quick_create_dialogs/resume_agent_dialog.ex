defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs.ResumeAgentDialog do
  @moduledoc false
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents

  def quick_resume_agent(assigns) do
    ~H"""
    <dialog
      id="quick-resume-agent"
      phx-hook="QuickResumeAgent"
      class="modal modal-bottom sm:modal-middle p-0 bg-transparent"
    >
      <div class="modal-box max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-base-content">Resume Agent</h2>
          <button
            data-qra-cancel
            type="button"
            class="btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px]"
            aria-label="Close"
          >
            <span class="hero-x-mark w-4 h-4"></span>
          </button>
        </div>
        <form data-qra-form class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qra-agent-uuid">Agent UUID</label>
            <input
              id="qra-agent-uuid"
              data-qra-agent-uuid
              required
              placeholder="Enter agent UUID to resume"
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base min-h-[44px]"
            />
          </div>
          <div>
            <label class="sr-only" for="qra-instructions">Instructions (optional)</label>
            <textarea
              id="qra-instructions"
              data-qra-instructions
              placeholder="New instructions (optional - uses original if blank)"
              rows="4"
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base resize-none"
            ></textarea>
          </div>
          <div class="alert alert-info text-sm">
            <.icon name="hero-information-circle" class="shrink-0 w-5 h-5" />
            <span>This will spawn a new Claude session for the existing agent.</span>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qra-cancel type="button" class="btn btn-ghost btn-sm min-h-[44px]">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary btn-sm min-h-[44px]">Resume Agent</button>
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
