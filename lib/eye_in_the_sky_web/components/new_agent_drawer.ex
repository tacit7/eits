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
                <.icon name="hero-adjustments-horizontal" class="size-3.5" /> Advanced
              </div>
              <div class="collapse-content px-3 pb-3 space-y-3">

                <!-- Execution -->
                <p class="text-xs font-semibold text-base-content/40 uppercase tracking-wide pt-1">Execution</p>

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
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--max-turns</span>
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
                    <span class="label-text text-xs">Fallback Model</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--fallback-model</span>
                  </label>
                  <input
                    type="text"
                    name="fallback_model"
                    placeholder="e.g., claude-sonnet-4-6"
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">From PR</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--from-pr</span>
                  </label>
                  <input
                    type="number"
                    name="from_pr"
                    min="1"
                    placeholder="PR number"
                    class="input input-bordered input-sm w-full font-mono min-h-[44px]"
                  />
                </div>

                <!-- Output / Print Mode -->
                <p class="text-xs font-semibold text-base-content/40 uppercase tracking-wide pt-1">Output / Print Mode</p>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Output Format</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--output-format</span>
                  </label>
                  <select name="output_format" class="select select-bordered select-sm w-full">
                    <option value="">Default (text)</option>
                    <option value="text">text</option>
                    <option value="json">json — structured results + metadata</option>
                    <option value="stream-json">stream-json — real-time streaming</option>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Input Format</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--input-format</span>
                  </label>
                  <select name="input_format" class="select select-bordered select-sm w-full">
                    <option value="">Default (text)</option>
                    <option value="text">text</option>
                    <option value="stream-json">stream-json</option>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">JSON Schema</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--json-schema</span>
                  </label>
                  <textarea
                    name="json_schema"
                    rows="3"
                    placeholder='{"type":"object","properties":{"result":{"type":"string"}}}'
                    class="textarea textarea-bordered textarea-sm w-full font-mono text-xs"
                  ></textarea>
                </div>

                <!-- Scripting -->
                <p class="text-xs font-semibold text-base-content/40 uppercase tracking-wide pt-1">Scripting</p>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Allowed Tools</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--allowedTools</span>
                  </label>
                  <input
                    type="text"
                    name="allowed_tools"
                    placeholder='Bash(git *) Read Edit'
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Permission Prompt Tool</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--permission-prompt-tool</span>
                  </label>
                  <input
                    type="text"
                    name="permission_prompt_tool"
                    placeholder="mcp__server__tool_name"
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <!-- Paths -->
                <p class="text-xs font-semibold text-base-content/40 uppercase tracking-wide pt-1">Paths</p>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Add Directory</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--add-dir</span>
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
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--mcp-config</span>
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
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--plugin-dir</span>
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
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--settings</span>
                  </label>
                  <input
                    type="text"
                    name="settings_file"
                    placeholder="./settings.json"
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Agents JSON</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--agents</span>
                  </label>
                  <textarea
                    name="agents_json"
                    rows="3"
                    placeholder='[{"name":"reviewer","system_prompt":"..."}]'
                    class="textarea textarea-bordered textarea-sm w-full font-mono text-xs"
                  ></textarea>
                </div>

                <!-- System Prompt -->
                <p class="text-xs font-semibold text-base-content/40 uppercase tracking-wide pt-1">System Prompt</p>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Agent Persona</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--agent</span>
                  </label>
                  <input
                    type="text"
                    name="agent_flag"
                    placeholder="named agent persona"
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">System Prompt</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--system-prompt</span>
                  </label>
                  <textarea
                    name="system_prompt"
                    rows="3"
                    placeholder="Replaces the default system prompt..."
                    class="textarea textarea-bordered textarea-sm w-full text-xs"
                  ></textarea>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">System Prompt File</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--system-prompt-file</span>
                  </label>
                  <input
                    type="text"
                    name="system_prompt_file"
                    placeholder="./system.md"
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Append System Prompt</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--append-system-prompt</span>
                  </label>
                  <textarea
                    name="append_system_prompt"
                    rows="3"
                    placeholder="Appended to the default system prompt..."
                    class="textarea textarea-bordered textarea-sm w-full text-xs"
                  ></textarea>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Append System Prompt File</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--append-system-prompt-file</span>
                  </label>
                  <input
                    type="text"
                    name="append_system_prompt_file"
                    placeholder="./extra-rules.md"
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <!-- Debug & Safety -->
                <p class="text-xs font-semibold text-base-content/40 uppercase tracking-wide pt-1">Debug & Safety</p>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-xs">Debug Categories</span>
                    <span class="label-text-alt text-base-content/40 font-mono text-xs">--debug</span>
                  </label>
                  <input
                    type="text"
                    name="debug"
                    placeholder="api hooks"
                    class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
                  />
                </div>

                <div class="flex flex-col gap-1 pt-1">
                  <label class="label cursor-pointer justify-start gap-2 py-1">
                    <input type="checkbox" name="bare" value="true" class="checkbox checkbox-sm checkbox-primary" />
                    <span class="label-text text-xs">
                      Bare mode — skip hook/skill/MCP discovery
                      <span class="font-mono text-base-content/40 text-xs ml-1">--bare</span>
                    </span>
                  </label>
                  <label class="label cursor-pointer justify-start gap-2 py-1">
                    <input type="checkbox" name="verbose" value="true" class="checkbox checkbox-sm checkbox-primary" />
                    <span class="label-text text-xs">
                      Verbose output
                      <span class="font-mono text-base-content/40 text-xs ml-1">--verbose</span>
                    </span>
                  </label>
                  <label class="label cursor-pointer justify-start gap-2 py-1">
                    <input type="checkbox" name="include_partial_messages" value="true" class="checkbox checkbox-sm checkbox-primary" />
                    <span class="label-text text-xs">
                      Include partial messages
                      <span class="font-mono text-base-content/40 text-xs ml-1">--include-partial-messages</span>
                    </span>
                  </label>
                  <label class="label cursor-pointer justify-start gap-2 py-1">
                    <input type="checkbox" name="no_session_persistence" value="true" class="checkbox checkbox-sm checkbox-primary" />
                    <span class="label-text text-xs">
                      No session persistence
                      <span class="font-mono text-base-content/40 text-xs ml-1">--no-session-persistence</span>
                    </span>
                  </label>
                  <label class="label cursor-pointer justify-start gap-2 py-1">
                    <input type="checkbox" name="chrome" value="true" class="checkbox checkbox-sm checkbox-primary" />
                    <span class="label-text text-xs">
                      Chrome integration
                      <span class="font-mono text-base-content/40 text-xs ml-1">--chrome</span>
                    </span>
                  </label>
                  <label class="label cursor-pointer justify-start gap-2 py-1">
                    <input type="checkbox" name="sandbox" value="true" class="checkbox checkbox-sm checkbox-primary" />
                    <span class="label-text text-xs">
                      OS sandbox isolation
                      <span class="font-mono text-base-content/40 text-xs ml-1">--sandbox</span>
                    </span>
                  </label>
                  <label class="label cursor-pointer justify-start gap-2 py-1">
                    <input type="checkbox" name="dangerously_skip_permissions" value="true" class="checkbox checkbox-sm checkbox-error" />
                    <span class="label-text text-xs">
                      <span class="text-error">Dangerously skip permissions</span>
                      <span class="font-mono text-base-content/40 text-xs ml-1">--dangerously-skip-permissions</span>
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
