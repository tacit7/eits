defmodule EyeInTheSkyWebWeb.Components.NewAgentDrawer do
  @moduledoc """
  Reusable New Agent drawer component for channel agent creation.
  """

  use Phoenix.LiveComponent
  import EyeInTheSkyWebWeb.CoreComponents, only: [form_actions: 1, form_field: 1, modal_header: 1]
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
          <.modal_header title="New Agent" toggle_event={@toggle_event} />

          <form phx-submit={@submit_event} class="flex flex-col gap-4">
            <!-- Agent Type -->
            <.form_field label="Agent Type">
              <select name="agent_type" class="select select-bordered" required>
                <option value="claude">Claude</option>
                <option value="codex">Codex</option>
              </select>
            </.form_field>

            <!-- Model Selection Dropdown -->
            <.form_field label="Model">
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
            </.form_field>

            <!-- Effort Level (Opus & Sonnet) -->
            <.form_field label="Effort Level" hint="(Opus & Sonnet)">
              <select name="effort_level" class="select select-bordered">
                <option value="">-- Default (high) --</option>
                <option value="low">Low • Faster and cheaper</option>
                <option value="medium">Medium • Balanced approach</option>
                <option value="high">High • Deeper reasoning (default)</option>
              </select>
            </.form_field>

            <!-- Max Budget -->
            <.form_field label="Max Budget (USD)" hint="Optional — blank = unlimited">
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
            </.form_field>

            <!-- Prompt Template -->
            <.form_field label="Prompt Template" hint="Optional">
              <select name="prompt_id" class="select select-bordered">
                <option value="">-- None (Custom Instructions) --</option>
                <%= for prompt <- @prompts do %>
                  <option value={prompt.id}>{prompt.name}</option>
                <% end %>
              </select>
            </.form_field>

            <!-- Agent Name / Nickname -->
            <.form_field label="Agent Name / Nickname">
              <input
                type="text"
                name="description"
                class="input input-bordered"
                placeholder="e.g., Code Reviewer, Bug Fixer..."
              />
            </.form_field>

            <!-- Instructions -->
            <.form_field label="Instructions">
              <textarea
                name="instructions"
                class="textarea textarea-bordered h-24"
                placeholder="What should this agent do?"
                required
              ></textarea>
            </.form_field>

            <!-- Worktree / Branch -->
            <.form_field label="Worktree Branch" hint="Optional — isolates work + enables PR">
              <input
                type="text"
                name="worktree"
                class="input input-bordered font-mono text-sm"
                placeholder="e.g., fix-login-bug"
              />
              <label class="label">
                <span class="label-text-alt text-base-content/40">Branch: worktree-&lt;name&gt;</span>
              </label>
            </.form_field>
            
    <!-- Actions -->
            <.form_actions submit_text="Create Agent" cancel_event={@toggle_event} class="mt-4" />
          </form>
        </div>
      </div>
    </div>
    """
  end
end
