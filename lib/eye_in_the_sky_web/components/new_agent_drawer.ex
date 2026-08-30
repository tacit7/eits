defmodule EyeInTheSkyWeb.Components.NewAgentDrawer do
  @moduledoc """
  Reusable New Agent drawer component for channel agent creation.
  """

  use Phoenix.LiveComponent

  import EyeInTheSkyWeb.CoreComponents,
    only: [form_actions: 1, form_field: 1, icon: 1, modal_header: 1]

  import EyeInTheSkyWeb.Components.CliFlags,
    only: [path_fields: 1, boolean_flags: 1]

  import EyeInTheSkyWeb.Components.ModelSelector, only: [model_selector: 1]

  alias EyeInTheSky.Agents.ModelConfig
  alias EyeInTheSky.Pi.ModelDiscoveryCache
  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  @impl true
  def mount(socket) do
    ModelDiscoveryCache.refresh_async()

    {:ok,
     assign(socket,
       pending_provider: "claude",
       pending_model: ModelHelpers.default_model_for("claude")
     )}
  end

  @impl true
  def handle_event(
        "model_and_provider_selected",
        %{"provider" => provider, "model" => model},
        socket
      ) do
    if ModelConfig.valid_model?(provider, model) do
      {:noreply, assign(socket, pending_provider: provider, pending_model: model)}
    else
      {:noreply, socket}
    end
  end

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
            <!-- Provider + Model -->
            <.form_field label="Model">
              <.model_selector
                id="new-agent-drawer-model-selector"
                entries={ModelHelpers.all_model_entries()}
                selected_provider={@pending_provider}
                selected_model={@pending_model}
                allow_provider_switch?={true}
                event="model_and_provider_selected"
                myself={@myself}
              />
              <input type="hidden" name="agent_type" value={@pending_provider} />
              <input type="hidden" name="model" value={@pending_model} />
            </.form_field>
            
    <!-- Effort Level (Opus & Sonnet) -->
            <.form_field label="Effort Level" hint="(Opus & Sonnet)">
              <select name="effort_level" class="select select-bordered">
                <option value="">-- Default (high) --</option>
                <option value="low">Low | Faster and cheaper</option>
                <option value="medium">Medium | Balanced approach</option>
                <option value="high">High | Deeper reasoning (default)</option>
                <option value="max">Max | Maximum effort</option>
              </select>
            </.form_field>
            
    <!-- Max Budget -->
            <.form_field label="Max Budget (USD)" hint="Optional | blank = unlimited">
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
                class="input input-bordered text-message"
                placeholder="e.g., Code Reviewer, Bug Fixer..."
              />
            </.form_field>
            
    <!-- Worktree / Branch -->
            <.form_field label="Worktree Branch" hint="Optional | isolates work + enables PR">
              <input
                type="text"
                name="worktree"
                class="input input-bordered font-mono text-message"
                placeholder="e.g., fix-login-bug"
              />
              <label class="label">
                <span class="label-text-alt text-base-content/40">Branch: worktree-&lt;name&gt;</span>
              </label>
            </.form_field>
            
    <!-- Advanced CLI Flags -->
            <.advanced_section />
            
    <!-- Actions -->
            <.form_actions submit_text="Create Agent" cancel_event={@toggle_event} class="mt-4" />
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp advanced_section(assigns) do
    ~H"""
    <div class="collapse collapse-arrow bg-base-200 rounded-box">
      <input type="checkbox" class="min-h-0" />
      <div class="collapse-title min-h-0 py-2.5 px-3 flex items-center gap-1.5 text-mini font-medium text-base-content/60">
        <.icon name="hero-adjustments-horizontal" class="size-3.5" /> Advanced
      </div>
      <div class="collapse-content px-3 pb-3 space-y-3">
        <.advanced_execution />
        <.advanced_output />
        <.advanced_scripting />
        <.advanced_paths />
        <.advanced_system_prompt />
        <.advanced_debug_safety />
      </div>
    </div>
    """
  end

  defp advanced_execution(assigns) do
    ~H"""
    <p class="text-mini font-semibold text-base-content/40 uppercase tracking-normal pt-1">
      Execution
    </p>

    <div class="form-control">
      <label class="label"><span class="label-text text-mini">Permission Mode</span></label>
      <select name="permission_mode" class="select select-bordered select-sm w-full">
        <option value="">Default</option>
        <option value="acceptEdits">acceptEdits | auto-accept file edits</option>
        <option value="bypassPermissions">bypassPermissions | skip all prompts</option>
        <option value="dontAsk">dontAsk | never ask for confirmation</option>
        <option value="plan">plan | read-only, no file changes</option>
      </select>
    </div>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">Max Turns</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">--max-turns</span>
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
        <span class="label-text text-mini">Fallback Model</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">--fallback-model</span>
      </label>
      <input
        type="text"
        name="fallback_model"
        placeholder="e.g., claude-sonnet-4-6"
        class="input input-bordered input-sm w-full font-mono text-message min-h-[44px]"
      />
    </div>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">From PR</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">--from-pr</span>
      </label>
      <input
        type="number"
        name="from_pr"
        min="1"
        placeholder="PR number"
        class="input input-bordered input-sm w-full font-mono min-h-[44px]"
      />
    </div>
    """
  end

  defp advanced_output(assigns) do
    ~H"""
    <p class="text-mini font-semibold text-base-content/40 uppercase tracking-normal pt-1">
      Output / Print Mode
    </p>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">Output Format</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">--output-format</span>
      </label>
      <select name="output_format" class="select select-bordered select-sm w-full">
        <option value="">Default (text)</option>
        <option value="text">text</option>
        <option value="json">json | structured results + metadata</option>
        <option value="stream-json">stream-json | real-time streaming</option>
      </select>
    </div>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">Input Format</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">--input-format</span>
      </label>
      <select name="input_format" class="select select-bordered select-sm w-full">
        <option value="">Default (text)</option>
        <option value="text">text</option>
        <option value="stream-json">stream-json</option>
      </select>
    </div>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">JSON Schema</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">--json-schema</span>
      </label>
      <textarea
        name="json_schema"
        rows="3"
        placeholder='{"type":"object","properties":{"result":{"type":"string"}}}'
        class="textarea textarea-bordered textarea-sm w-full font-mono text-mini"
      ></textarea>
    </div>
    """
  end

  defp advanced_scripting(assigns) do
    ~H"""
    <p class="text-mini font-semibold text-base-content/40 uppercase tracking-normal pt-1">
      Scripting
    </p>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">Allowed Tools</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">--allowedTools</span>
      </label>
      <input
        type="text"
        name="allowed_tools"
        placeholder="Bash(git *) Read Edit"
        class="input input-bordered input-sm w-full font-mono text-message min-h-[44px]"
      />
    </div>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">Permission Prompt Tool</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">
          --permission-prompt-tool
        </span>
      </label>
      <input
        type="text"
        name="permission_prompt_tool"
        placeholder="mcp__server__tool_name"
        class="input input-bordered input-sm w-full font-mono text-message min-h-[44px]"
      />
    </div>
    """
  end

  defp advanced_paths(assigns) do
    ~H"""
    <p class="text-mini font-semibold text-base-content/40 uppercase tracking-normal pt-1">Paths</p>
    <.path_fields />
    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">Agents JSON</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">--agents</span>
      </label>
      <textarea
        name="agents_json"
        rows="3"
        placeholder='[{"name":"reviewer","system_prompt":"..."}]'
        class="textarea textarea-bordered textarea-sm w-full font-mono text-mini"
      ></textarea>
    </div>
    """
  end

  defp advanced_system_prompt(assigns) do
    ~H"""
    <p class="text-mini font-semibold text-base-content/40 uppercase tracking-normal pt-1">
      System Prompt
    </p>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">Agent Persona</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">--agent</span>
      </label>
      <input
        type="text"
        name="agent_flag"
        placeholder="named agent persona"
        class="input input-bordered input-sm w-full font-mono text-message min-h-[44px]"
      />
    </div>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">System Prompt</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">--system-prompt</span>
      </label>
      <textarea
        name="system_prompt"
        rows="3"
        placeholder="Replaces the default system prompt..."
        class="textarea textarea-bordered textarea-sm w-full text-mini"
      ></textarea>
    </div>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">System Prompt File</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">
          --system-prompt-file
        </span>
      </label>
      <input
        type="text"
        name="system_prompt_file"
        placeholder="./system.md"
        class="input input-bordered input-sm w-full font-mono text-message min-h-[44px]"
      />
    </div>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">Append System Prompt</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">
          --append-system-prompt
        </span>
      </label>
      <textarea
        name="append_system_prompt"
        rows="3"
        placeholder="Appended to the default system prompt..."
        class="textarea textarea-bordered textarea-sm w-full text-mini"
      ></textarea>
    </div>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">Append System Prompt File</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">
          --append-system-prompt-file
        </span>
      </label>
      <input
        type="text"
        name="append_system_prompt_file"
        placeholder="./extra-rules.md"
        class="input input-bordered input-sm w-full font-mono text-message min-h-[44px]"
      />
    </div>
    """
  end

  defp advanced_debug_safety(assigns) do
    ~H"""
    <p class="text-mini font-semibold text-base-content/40 uppercase tracking-normal pt-1">
      Debug & Safety
    </p>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-mini">Debug Categories</span>
        <span class="label-text-alt text-base-content/40 font-mono text-mini">--debug</span>
      </label>
      <input
        type="text"
        name="debug"
        placeholder="api hooks"
        class="input input-bordered input-sm w-full font-mono text-message min-h-[44px]"
      />
    </div>

    <div class="flex flex-col gap-1 pt-1">
      <label class="label cursor-pointer justify-start gap-2 py-1">
        <input type="checkbox" name="bare" value="true" class="checkbox checkbox-sm checkbox-primary" />
        <span class="label-text text-mini">
          Bare mode | skip hook/skill/MCP discovery
          <span class="font-mono text-base-content/40 text-mini ml-1">--bare</span>
        </span>
      </label>
      <label class="label cursor-pointer justify-start gap-2 py-1">
        <input
          type="checkbox"
          name="verbose"
          value="true"
          class="checkbox checkbox-sm checkbox-primary"
        />
        <span class="label-text text-mini">
          Verbose output <span class="font-mono text-base-content/40 text-mini ml-1">--verbose</span>
        </span>
      </label>
      <label class="label cursor-pointer justify-start gap-2 py-1">
        <input
          type="checkbox"
          name="include_partial_messages"
          value="true"
          class="checkbox checkbox-sm checkbox-primary"
        />
        <span class="label-text text-mini">
          Include partial messages
          <span class="font-mono text-base-content/40 text-mini ml-1">
            --include-partial-messages
          </span>
        </span>
      </label>
      <label class="label cursor-pointer justify-start gap-2 py-1">
        <input
          type="checkbox"
          name="no_session_persistence"
          value="true"
          class="checkbox checkbox-sm checkbox-primary"
        />
        <span class="label-text text-mini">
          No session persistence
          <span class="font-mono text-base-content/40 text-mini ml-1">--no-session-persistence</span>
        </span>
      </label>
    </div>
    <.boolean_flags skip_permissions={true} />
    """
  end
end
