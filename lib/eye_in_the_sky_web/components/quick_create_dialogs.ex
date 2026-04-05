defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs do
  @moduledoc false
  use Phoenix.Component

  def quick_create_note(assigns) do
    ~H"""
    <dialog
      id="quick-create-note"
      phx-hook="QuickCreateNote"
      class="modal modal-bottom sm:modal-middle p-0 bg-transparent"
    >
      <div class="modal-box max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-base-content">New Note</h2>
          <button
            data-qcn-cancel
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            aria-label="Close"
          >
            <span class="hero-x-mark w-4 h-4"></span>
          </button>
        </div>
        <form data-qcn-form class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qcn-title">Title</label>
            <input
              id="qcn-title"
              type="text"
              data-qcn-title
              required
              placeholder="Note title..."
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm"
              autocomplete="off"
            />
          </div>
          <div>
            <label class="sr-only" for="qcn-body">Body</label>
            <textarea
              id="qcn-body"
              data-qcn-body
              placeholder="Note content..."
              rows="4"
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm resize-none"
            ></textarea>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qcn-cancel type="button" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm">Create Note</button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end

  attr :project_id, :any, default: nil

  def quick_create_agent(assigns) do
    ~H"""
    <dialog
      id="quick-create-agent"
      phx-hook="QuickCreateAgent"
      data-project-id={@project_id}
      class="modal modal-bottom sm:modal-middle p-0 bg-transparent"
    >
      <div class="modal-box max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-base-content">New Agent</h2>
          <button
            data-qca-cancel
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            aria-label="Close"
          >
            <span class="hero-x-mark w-4 h-4"></span>
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
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm resize-none"
            ></textarea>
          </div>
          <div>
            <label class="sr-only" for="qca-parent-session">Parent Session UUID (optional)</label>
            <input
              id="qca-parent-session"
              data-qca-parent-session
              placeholder="Parent session UUID (optional)"
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm"
            />
          </div>
          <div>
            <label class="sr-only" for="qca-model">Model</label>
            <select
              id="qca-model"
              data-qca-model
              class="select select-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm"
            >
              <option value="haiku">Haiku (fast)</option>
              <option value="sonnet">Sonnet (balanced)</option>
            </select>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qca-cancel type="button" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm">Spawn Agent</button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end

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
            class="btn btn-ghost btn-xs btn-square"
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
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm"
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
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm resize-none"
            ></textarea>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qua-cancel type="button" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm">Update Agent</button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end

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
            class="btn btn-ghost btn-xs btn-square"
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
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm"
            />
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qga-cancel type="button" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm">Get Details</button>
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
            class="btn btn-ghost btn-xs btn-square"
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
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm"
            />
          </div>
          <div class="alert alert-warning text-sm">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="stroke-current shrink-0 h-5 w-5"
              fill="none"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
              />
            </svg>
            <span>Warning: This action cannot be undone. The agent will be permanently deleted.</span>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qda-cancel type="button" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-error btn-sm">Delete Agent</button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end

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
            class="btn btn-ghost btn-xs btn-square"
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
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm"
            />
          </div>
          <div>
            <label class="sr-only" for="qra-instructions">Instructions (optional)</label>
            <textarea
              id="qra-instructions"
              data-qra-instructions
              placeholder="New instructions (optional - uses original if blank)"
              rows="4"
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm resize-none"
            ></textarea>
          </div>
          <div class="alert alert-info text-sm">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              class="stroke-current shrink-0 w-5 h-5"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              ></path>
            </svg>
            <span>This will spawn a new Claude session for the existing agent.</span>
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qra-cancel type="button" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm">Resume Agent</button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end

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
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm"
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

  attr :project_id, :any, default: nil

  def quick_create_task(assigns) do
    ~H"""
    <dialog
      id="quick-create-task"
      phx-hook="QuickCreateTask"
      data-project-id={@project_id}
      class="modal modal-bottom sm:modal-middle p-0 bg-transparent"
    >
      <div class="modal-box max-w-lg p-0 overflow-hidden">
        <div class="border-b border-base-content/10 px-4 py-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-base-content">New Task</h2>
          <button
            data-qct-cancel
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            aria-label="Close"
          >
            <span class="hero-x-mark w-4 h-4"></span>
          </button>
        </div>
        <form data-qct-form class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qct-title">Title</label>
            <input
              id="qct-title"
              type="text"
              data-qct-title
              required
              placeholder="Task title..."
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm"
              autocomplete="off"
            />
          </div>
          <div>
            <label class="sr-only" for="qct-description">Description</label>
            <textarea
              id="qct-description"
              data-qct-description
              placeholder="Description (optional)..."
              rows="3"
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm resize-none"
            ></textarea>
          </div>
          <div>
            <label class="sr-only" for="qct-tags">Tags</label>
            <input
              id="qct-tags"
              type="text"
              data-qct-tags
              placeholder="tag1, tag2, tag3"
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-sm"
              autocomplete="off"
            />
          </div>
          <div class="flex justify-end gap-2 pt-1">
            <button data-qct-cancel type="button" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm">Create Task</button>
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
