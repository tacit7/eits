defmodule EyeInTheSkyWebWeb.Components.NewAgentDrawer do
  @moduledoc """
  Reusable New Agent drawer component for channel agent creation.
  """

  use Phoenix.LiveComponent
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers, only: [claude_models: 0, codex_models: 0]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="drawer drawer-end">
      <input
        id="new-agent-drawer"
        type="checkbox"
        class="drawer-toggle"
        checked={@show}
        phx-click={@toggle_event}
      />
      <div class="drawer-side z-50">
        <label for="new-agent-drawer" class="drawer-overlay"></label>
        <div
          id="new-agent-panel"
          phx-hook="DrawerSwipeClose"
          data-close-event={@toggle_event}
          class="menu p-6 w-96 min-h-full bg-base-100 text-base-content"
        >
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-xl font-semibold">New Agent</h2>
            <button phx-click={@toggle_event} class="btn btn-ghost btn-sm btn-circle">✕</button>
          </div>

          <form phx-submit={@submit_event} class="flex flex-col gap-4">
            <!-- Agent Type -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Agent Type</span>
              </label>
              <select name="agent_type" class="select select-bordered" required>
                <option value="claude">Claude</option>
                <option value="codex">Codex</option>
              </select>
            </div>
            
    <!-- Model Selection Dropdown -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Model</span>
              </label>
              <select name="model" class="select select-bordered" required>
                <optgroup label="Claude">
                  <%= for {value, label} <- claude_models() do %>
                    <option value={value}>{label}</option>
                  <% end %>
                </optgroup>
                <optgroup label="Codex">
                  <%= for {value, label} <- codex_models() do %>
                    <option value={value}>{label}</option>
                  <% end %>
                </optgroup>
              </select>
            </div>
            
    <!-- Effort Level (Opus & Sonnet) -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Effort Level</span>
                <span class="label-text-alt text-xs">(Opus & Sonnet)</span>
              </label>
              <select name="effort_level" class="select select-bordered">
                <option value="">-- Default (high) --</option>
                <option value="low">Low • Faster and cheaper</option>
                <option value="medium">Medium • Balanced approach</option>
                <option value="high">High • Deeper reasoning (default)</option>
              </select>
            </div>
            
    <!-- Max Budget -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Max Budget (USD)</span>
                <span class="label-text-alt text-xs">Optional — blank = unlimited</span>
              </label>
              <label class="input input-bordered flex items-center gap-1">
                <span class="text-base-content/50 font-mono">$</span>
                <input
                  type="number"
                  name="max_budget_usd"
                  min="0"
                  step="0.01"
                  placeholder="unlimited"
                  class="grow bg-transparent border-0 outline-none focus:ring-0"
                />
              </label>
            </div>

    <!-- Prompt Template -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Prompt Template</span>
                <span class="label-text-alt">Optional</span>
              </label>
              <select name="prompt_id" class="select select-bordered">
                <option value="">-- None (Custom Instructions) --</option>
                <%= for prompt <- @prompts do %>
                  <option value={prompt.id}>{prompt.name}</option>
                <% end %>
              </select>
            </div>
            
    <!-- Agent Name / Nickname -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Agent Name / Nickname</span>
              </label>
              <input
                type="text"
                name="description"
                class="input input-bordered"
                placeholder="e.g., Code Reviewer, Bug Fixer..."
              />
            </div>
            
    <!-- Instructions -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Instructions</span>
              </label>
              <textarea
                name="instructions"
                class="textarea textarea-bordered h-24"
                placeholder="What should this agent do?"
                required
              ></textarea>
            </div>
            
    <!-- Worktree / Branch -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Worktree Branch</span>
                <span class="label-text-alt text-xs">Optional — isolates work + enables PR</span>
              </label>
              <input
                type="text"
                name="worktree"
                class="input input-bordered font-mono text-sm"
                placeholder="e.g., fix-login-bug"
              />
              <label class="label">
                <span class="label-text-alt text-base-content/40">Branch: worktree-&lt;name&gt;</span>
              </label>
            </div>
            
    <!-- Actions -->
            <div class="flex gap-2 mt-4">
              <button type="submit" class="btn btn-primary flex-1">Create Agent</button>
              <button type="button" phx-click={@toggle_event} class="btn btn-ghost flex-shrink-0">
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
