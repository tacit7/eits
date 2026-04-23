defmodule EyeInTheSkyWeb.Components.NewAgentDrawer do
  @moduledoc """
  Reusable New Agent drawer component for channel agent creation.
  """

  use Phoenix.LiveComponent

  import EyeInTheSkyWeb.CoreComponents,
    only: [form_actions: 1, form_field: 1, icon: 1, modal_header: 1]

  import EyeInTheSkyWeb.Helpers.ViewHelpers,
    only: [claude_models: 0, codex_models: 0, gemini_models: 0]

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
          class="menu p-6 w-full max-w-sm min-h-full bg-base-100 text-base-content"
        >
          <.modal_header title="New Agent" toggle_event={@toggle_event} />

          <form phx-submit={@submit_event} class="flex flex-col gap-4">
            <!-- Agent Type -->
            <.form_field label="Agent Type">
              <select name="agent_type" class="select select-bordered" required>
                <option value="claude">Claude</option>
                <option value="codex">Codex</option>
                <option value="gemini">Gemini</option>
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
                <optgroup label="Gemini">
                  <%= for {value, label} <- gemini_models() do %>
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
                <option value="max">Max • Maximum effort</option>
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
                name="agent_name"
                class="input input-bordered text-base"
                placeholder="e.g., Code Reviewer, Bug Fixer..."
              />
            </.form_field>
            
    <!-- Instructions -->
            <.form_field label="Instructions">
              <textarea
                name="description"
                class="textarea textarea-bordered h-24 text-base"
                placeholder="What should this agent do?"
                required
              ></textarea>
            </.form_field>
            
    <!-- Worktree / Branch -->
            <.form_field label="Worktree Branch" hint="Optional — isolates work + enables PR">
              <input
                type="text"
                name="worktree"
                class="input input-bordered font-mono text-base"
                placeholder="e.g., fix-login-bug"
              />
              <label class="label">
                <span class="label-text-alt text-base-content/40">Branch: worktree-&lt;name&gt;</span>
              </label>
            </.form_field>
            
    <!-- Advanced CLI Flags -->
            <div class="collapse collapse-arrow bg-base-200 rounded-lg">
              <input type="checkbox" class="min-h-0" />
              <div class="collapse-title min-h-0 py-2.5 px-3 flex items-center gap-1.5 text-xs font-medium text-base-content/60">
                <.icon name="hero-adjustments-horizontal" class="w-3.5 h-3.5" /> Advanced
              </div>
              <div class="collapse-content px-3 pb-3 space-y-3">
                <div class="form-control">
                  <label class="label"><span class="label-text text-xs">Permission Mode</span></label>
                  <select name="permission_mode" class="select select-bordered select-sm w-full">
                    <option value="">Default</option>
                    <option value="acceptEdits">acceptEdits — auto-accept file edits</option>
                    <option value="bypassPermissions">bypassPermissions — skip all prompts</option>
                    <option value="dontAsk">dontAsk — never ask for confirmation</option>
                    <option value="plan">plan — read-only, no file changes</option>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Max Turns</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">
                      --max-turns
                    </span>
                  </label>
                  <input
                    type="number"
                    name="max_turns"
                    min="1"
                    placeholder="unlimited"
                    class="input input-bordered input-sm w-full font-mono min-h-[44px]"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Add Directory</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">
                      --add-dir
                    </span>
                  </label>
                  <input
                    type="text"
                    name="add_dir"
                    placeholder="/path/to/shared-lib"
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">MCP Config File</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">
                      --mcp-config
                    </span>
                  </label>
                  <input
                    type="text"
                    name="mcp_config"
                    placeholder="./mcp-servers.json"
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Plugin Directory</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">
                      --plugin-dir
                    </span>
                  </label>
                  <input
                    type="text"
                    name="plugin_dir"
                    placeholder="./my-plugins"
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Settings File</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">
                      --settings
                    </span>
                  </label>
                  <input
                    type="text"
                    name="settings_file"
                    placeholder="./settings.json"
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <div class="flex flex-col gap-1 pt-1">
                  <label class="label cursor-pointer justify-start gap-2 py-1">
                    <input
                      type="checkbox"
                      name="chrome"
                      value="true"
                      class="checkbox checkbox-sm checkbox-primary"
                    />
                    <span class="label-text text-xs">
                      Chrome integration
                      <span class="font-mono text-base-content/40 text-xs ml-1">--chrome</span>
                    </span>
                  </label>
                  <label class="label cursor-pointer justify-start gap-2 py-1">
                    <input
                      type="checkbox"
                      name="sandbox"
                      value="true"
                      class="checkbox checkbox-sm checkbox-primary"
                    />
                    <span class="label-text text-xs">
                      OS sandbox isolation
                      <span class="font-mono text-base-content/40 text-xs ml-1">--sandbox</span>
                    </span>
                  </label>
                </div>
              </div>
            </div>
            
    <!-- Actions -->
            <.form_actions submit_text="Create Agent" cancel_event={@toggle_event} class="mt-4" />
          </form>
        </div>
      </div>
    </div>
    """
  end
end
