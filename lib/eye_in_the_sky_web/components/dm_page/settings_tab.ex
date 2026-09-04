defmodule EyeInTheSkyWeb.Components.DmPage.SettingsTab do
  @moduledoc """
  Settings tab for the DM page.

  Layout:
    * Scope toggle (pinned)    | Session | Agent. Controls where writes land.
    * Sub-tabs                 | General | Claude flags | Codex flags.
                                 Claude/Codex sub-tabs are hidden based on
                                 @session.provider.
  """
  use EyeInTheSkyWeb, :html

  attr :scope, :string, default: "session"
  attr :subtab, :string, default: "general"
  attr :session, :map, required: true
  attr :agent, :map, default: nil
  attr :session_state, :map, required: true
  attr :notify_on_stop, :boolean, default: false
  attr :overrides, :list, default: []
  # Full merged effective (defaults ⊕ agent ⊕ session). Used when scope="session".
  attr :effective, :map, default: %{}
  # Agent-only effective (defaults ⊕ agent, no session override). Used when scope="agent".
  attr :agent_effective, :map, default: %{}

  def settings_tab(assigns) do
    # Render inputs from the scope-appropriate effective map so agent scope shows
    # agent-level values instead of the session-merged result.
    scoped_effective =
      if assigns.scope == "agent", do: assigns.agent_effective, else: assigns.effective

    assigns =
      assigns
      |> assign(:scoped_effective, scoped_effective)
      |> assign(:active_subtab, active_subtab(assigns.subtab, assigns.session.provider))

    ~H"""
    <div class="space-y-4" id="dm-settings-tab">
      <.scope_toggle scope={@scope} agent={@agent} />

      <.subtab_nav subtab={@active_subtab} provider={@session.provider} />

      <div class="bg-base-200 rounded-box shadow-sm">
        <%= case @active_subtab do %>
          <% "general" -> %>
            <.general_section
              scope={@scope}
              session={@session}
              session_state={@session_state}
              effective={@scoped_effective}
              overrides={@overrides}
            />
          <% "anthropic" -> %>
            <.anthropic_section scope={@scope} effective={@scoped_effective} />
          <% "openai" -> %>
            <.openai_section scope={@scope} effective={@scoped_effective} />
          <% _ -> %>
            <.general_section
              scope={@scope}
              session={@session}
              session_state={@session_state}
              effective={@scoped_effective}
              overrides={@overrides}
            />
        <% end %>
      </div>

      <div class="flex items-center justify-end gap-2 pb-2">
        <button
          type="button"
          id="dm-settings-reset"
          class="eits-action eits-action--ghost h-7 min-h-0 px-2"
          phx-click="reset_dm_settings"
          phx-value-scope={@scope}
        >
          Reset {String.capitalize(@scope)} settings
        </button>
      </div>
    </div>
    """
  end

  # -- scope toggle ----------------------------------------------------------

  attr :scope, :string, required: true
  attr :agent, :map, default: nil

  defp scope_toggle(assigns) do
    ~H"""
    <div class="flex items-center justify-between bg-base-200 rounded-box shadow-sm px-4 py-3">
      <div>
        <div class="text-message font-medium">Saving to</div>
        <div class="text-mini text-base-content/50">
          {scope_help(@scope)}
        </div>
      </div>
      <div class="flex items-center gap-1 rounded-box bg-base-content/5 p-0.5">
        <button
          type="button"
          id="dm-scope-session"
          class={[
            "eits-action",
            if(@scope == "session", do: "eits-action--primary", else: "eits-action--ghost")
          ]}
          phx-click="dm_setting_scope"
          phx-value-scope="session"
        >
          This session
        </button>
        <button
          type="button"
          id="dm-scope-agent"
          class={[
            "eits-action",
            if(@scope == "agent", do: "eits-action--primary", else: "eits-action--ghost")
          ]}
          phx-click="dm_setting_scope"
          phx-value-scope="agent"
          disabled={is_nil(@agent)}
        >
          Agent default
        </button>
      </div>
    </div>
    """
  end

  defp scope_help("session"),
    do: "Changes apply to this session only. Reverts to agent defaults if reset."

  defp scope_help("agent"),
    do: "Changes apply to every future session spawned from this agent."

  defp scope_help(_), do: ""

  # -- sub-tab nav -----------------------------------------------------------

  attr :subtab, :string, required: true
  attr :provider, :string, default: nil

  defp subtab_nav(assigns) do
    ~H"""
    <div role="tablist" class="tabs tabs-bordered">
      <.subtab_button subtab={@subtab} value="general" label="General" />
      <.subtab_button
        :if={@provider == "claude"}
        subtab={@subtab}
        value="anthropic"
        label="Claude flags"
      />
      <.subtab_button
        :if={@provider == "codex"}
        subtab={@subtab}
        value="openai"
        label="Codex flags"
      />
    </div>
    """
  end

  attr :subtab, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true

  defp subtab_button(assigns) do
    ~H"""
    <button
      type="button"
      id={"dm-subtab-#{@value}"}
      role="tab"
      class={["tab", @subtab == @value && "tab-active"]}
      phx-click="dm_setting_subtab"
      phx-value-subtab={@value}
    >
      {@label}
    </button>
    """
  end

  # Falls back to "general" when the chosen subtab is incompatible with the provider
  # or is an unknown/nil value.
  defp active_subtab("anthropic", provider) when provider != "claude", do: "general"
  defp active_subtab("openai", provider) when provider != "codex", do: "general"
  defp active_subtab(subtab, _) when subtab in ["general", "anthropic", "openai"], do: subtab
  defp active_subtab(_, _), do: "general"

  # -- GENERAL ---------------------------------------------------------------

  attr :scope, :string, required: true
  attr :session, :map, required: true
  attr :session_state, :map, required: true

  # Scope-appropriate effective map | agent-only when scope="agent", merged when scope="session".
  attr :effective, :map, default: %{}
  attr :overrides, :list, default: []

  defp general_section(assigns) do
    ~H"""
    <.section title="Model">
      <.row
        label="Model"
        help="Used for new messages in this session"
        override={"model" in @overrides}
      >
        <div class="font-mono text-message text-base-content/80">
          {@session_state.model || "-"}
        </div>
      </.row>
      <.row
        :if={@session.provider == "codex"}
        label="Effort"
        help="Codex reasoning effort level"
        override={"effort" in @overrides}
      >
        <div class="font-mono text-message text-base-content/80">
          {@session_state.effort || "-"}
        </div>
      </.row>
      <.row
        label="Max budget (USD)"
        help="Session halts once spend exceeds this"
        override={"max_budget_usd" in @overrides}
      >
        <.num_input
          key="general.max_budget_usd"
          scope={@scope}
          value={get_in(@effective, ["general", "max_budget_usd"])}
          step="any"
          min="0"
        />
      </.row>
    </.section>

    <.divider />

    <.section title="Display">
      <.row
        label="Live stream"
        help="Show streaming tokens as the agent responds"
        override={"show_live_stream" in @overrides}
      >
        <.toggle
          key="general.show_live_stream"
          scope={@scope}
          checked={get_in(@effective, ["general", "show_live_stream"]) != false}
        />
      </.row>
      <.row
        label="Thinking"
        help="Show Claude's extended thinking blocks inline"
        override={"thinking_enabled" in @overrides}
      >
        <.toggle
          key="general.thinking_enabled"
          scope={@scope}
          checked={get_in(@effective, ["general", "thinking_enabled"]) == true}
        />
      </.row>
    </.section>

    <.divider />

    <.section title="Notifications">
      <.row
        label="Notify on stop"
        help="Desktop notification when the agent goes idle"
        override={"notify_on_stop" in @overrides}
      >
        <.toggle
          key="general.notify_on_stop"
          scope={@scope}
          checked={get_in(@effective, ["general", "notify_on_stop"]) == true}
        />
      </.row>
    </.section>
    """
  end

  # -- CLAUDE / ANTHROPIC FLAGS ---------------------------------------------

  attr :scope, :string, required: true
  attr :effective, :map, default: %{}

  defp anthropic_section(assigns) do
    ~H"""
    <.anthropic_execution scope={@scope} effective={@effective} />
    <.divider />
    <.anthropic_output scope={@scope} effective={@effective} />
    <.divider />
    <.anthropic_scripting scope={@scope} effective={@effective} />
    <.divider />
    <.anthropic_paths scope={@scope} effective={@effective} />
    <.divider />
    <.anthropic_prompt scope={@scope} effective={@effective} />
    <.divider />
    <.anthropic_debug scope={@scope} effective={@effective} />
    <.divider />
    <.anthropic_safety scope={@scope} effective={@effective} />
    """
  end

  attr :scope, :string, required: true
  attr :effective, :map, default: %{}

  defp anthropic_execution(assigns) do
    ~H"""
    <.section title="Execution">
      <.row
        label="Permission mode"
        help="--permission-mode"
        description="Sets how much autonomy Claude has when it starts. Common modes: default (asks before every edit), plan (read-only research), auto (AI classifier approves safe actions)."
      >
        <.select_input
          key="anthropic.permission_mode"
          scope={@scope}
          value={setting_val(@effective, "anthropic.permission_mode") || "acceptEdits"}
          options={["default", "acceptEdits", "plan", "bypassPermissions"]}
        />
      </.row>
      <.row
        label="Max turns"
        help="--max-turns"
        description="Non-interactive mode (-p) only. Limits how many back-and-forth steps Claude can take before the process stops with an error. No limit by default."
      >
        <.num_input
          key="anthropic.max_turns"
          scope={@scope}
          value={setting_val(@effective, "anthropic.max_turns")}
          placeholder="No limit"
          step="1"
          min="1"
        />
      </.row>
      <.row
        label="Fallback model"
        help="--fallback-model"
        description="Non-interactive mode only. Automatically switches to this model if the primary is overloaded or hits a rate limit."
      >
        <.select_input
          key="anthropic.fallback_model"
          scope={@scope}
          value={setting_val(@effective, "anthropic.fallback_model") || ""}
          options={["", "opus", "sonnet", "haiku"]}
        />
      </.row>
      <.row
        :if={@scope == "session"}
        label="From PR"
        help="--from-pr"
        description="Resumes a conversation linked to a GitHub pull request. Sessions are auto-linked when you use gh pr create while Claude is working."
      >
        <.text_input
          key="anthropic.from_pr"
          scope={@scope}
          value={setting_val(@effective, "anthropic.from_pr") || ""}
          placeholder="owner/repo#123"
        />
      </.row>
    </.section>
    """
  end

  attr :scope, :string, required: true
  attr :effective, :map, default: %{}

  defp anthropic_output(assigns) do
    ~H"""
    <.section title="Output">
      <.row
        label="JSON schema"
        help="--json-schema"
        description="Forces Claude to return a response that validates against a specific JSON structure. Useful when scripts need to parse output programmatically."
      >
        <.text_input
          key="anthropic.json_schema"
          scope={@scope}
          value={setting_val(@effective, "anthropic.json_schema") || ""}
          placeholder="path or inline"
        />
      </.row>
    </.section>
    """
  end

  attr :scope, :string, required: true
  attr :effective, :map, default: %{}

  defp anthropic_scripting(assigns) do
    ~H"""
    <.section title="Scripting">
      <.row
        label="Allowed tools"
        help="--allowedTools"
        description="List of tools (Read, Edit, Bash...) Claude can use without asking for permission."
      >
        <.text_input
          key="anthropic.allowed_tools"
          scope={@scope}
          value={setting_val(@effective, "anthropic.allowed_tools") || ""}
          placeholder="Read, Edit, Bash"
        />
      </.row>
      <.row
        label="Permission prompt tool"
        help="--permission-prompt-tool"
        description="MCP tool that handles permission requests automatically during non-interactive sessions."
      >
        <.text_input
          key="anthropic.permission_prompt_tool"
          scope={@scope}
          value={setting_val(@effective, "anthropic.permission_prompt_tool") || ""}
        />
      </.row>
    </.section>
    """
  end

  attr :scope, :string, required: true
  attr :effective, :map, default: %{}

  defp anthropic_paths(assigns) do
    ~H"""
    <.section title="Paths">
      <.row
        label="Add directory"
        help="--add-dir"
        description="Grants Claude access to folders outside the current project directory."
      >
        <.text_input
          key="anthropic.add_dir"
          scope={@scope}
          value={setting_val(@effective, "anthropic.add_dir") || ""}
          placeholder="/path/to/dir"
        />
      </.row>
      <.row
        label="MCP config file"
        help="--mcp-config"
        description="Loads MCP servers from a JSON file or string | Jira, Google Drive, other external data sources."
      >
        <.text_input
          key="anthropic.mcp_config"
          scope={@scope}
          value={setting_val(@effective, "anthropic.mcp_config") || ""}
        />
      </.row>
      <.row
        label="Plugin directory"
        help="--plugin-dir"
        description="Loads local plugins from a folder for this session. Useful for testing custom skills and agents before sharing."
      >
        <.text_input
          key="anthropic.plugin_dir"
          scope={@scope}
          value={setting_val(@effective, "anthropic.plugin_dir") || ""}
        />
      </.row>
      <.row
        label="Settings file"
        help="--settings"
        description="Loads additional configuration rules from a JSON file or string for this session."
      >
        <.text_input
          key="anthropic.settings_file"
          scope={@scope}
          value={setting_val(@effective, "anthropic.settings_file") || ""}
        />
      </.row>
      <.row
        label="Agents JSON"
        help="--agents"
        description="Define and configure custom subagents (with their own prompts and tools) inline via a JSON string."
      >
        <.text_input
          key="anthropic.agents_json"
          scope={@scope}
          value={setting_val(@effective, "anthropic.agents_json") || ""}
        />
      </.row>
    </.section>
    """
  end

  attr :scope, :string, required: true
  attr :effective, :map, default: %{}

  defp anthropic_prompt(assigns) do
    ~H"""
    <.section title="System prompt & agent type">
      <.row
        label="agent"
        help="--agent"
        description="Tells the main Claude session to adopt a named agent's persona, model, and tool restrictions (e.g. code-reviewer)."
      >
        <.text_input
          key="anthropic.agent_persona"
          scope={@scope}
          value={setting_val(@effective, "anthropic.agent_persona") || ""}
          placeholder="Agent Type"
        />
      </.row>
      <.row
        label="System prompt"
        help="--system-prompt"
        description="Completely replaces Claude Code's built-in instructions with your own text. Warning: removes tool knowledge unless you re-include it."
      >
        <.text_area
          key="anthropic.system_prompt"
          scope={@scope}
          value={setting_val(@effective, "anthropic.system_prompt") || ""}
        />
      </.row>
      <.row
        label="System prompt file"
        help="--system-prompt-file"
        description="Same as System prompt, but loaded from a file."
      >
        <.text_input
          key="anthropic.system_prompt_file"
          scope={@scope}
          value={setting_val(@effective, "anthropic.system_prompt_file") || ""}
        />
      </.row>
      <.row
        label="Append system prompt"
        help="--append-system-prompt"
        description="Adds your rules to the end of Claude's default instructions. Recommended for project rules (e.g. 'Always use TypeScript') | keeps tool abilities intact."
      >
        <.text_area
          key="anthropic.append_system_prompt"
          scope={@scope}
          value={setting_val(@effective, "anthropic.append_system_prompt") || ""}
        />
      </.row>
      <.row
        label="Append system prompt file"
        help="--append-system-prompt-file"
        description="Same as Append system prompt, but loaded from a file."
      >
        <.text_input
          key="anthropic.append_system_prompt_file"
          scope={@scope}
          value={setting_val(@effective, "anthropic.append_system_prompt_file") || ""}
        />
      </.row>
    </.section>
    """
  end

  attr :scope, :string, required: true
  attr :effective, :map, default: %{}

  defp anthropic_debug(assigns) do
    ~H"""
    <.section title="Debug">
      <.row
        label="Debug categories"
        help="--debug"
        description="Enables detailed logs for specific areas (api, mcp, hooks) to help troubleshoot."
      >
        <.text_input
          key="anthropic.debug_categories"
          scope={@scope}
          value={setting_val(@effective, "anthropic.debug_categories") || ""}
          placeholder="api,hooks"
        />
      </.row>
      <.row
        label="Bare mode"
        help="--bare"
        description="Starts Claude minimally | skips CLAUDE.md discovery, plugins, and skills. Recommended for fast-starting automated scripts."
      >
        <.toggle
          key="anthropic.bare"
          scope={@scope}
          checked={setting_val(@effective, "anthropic.bare") == true}
        />
      </.row>
      <.row
        label="Verbose"
        help="--verbose"
        description="Shows every step Claude takes | internal reasoning and exactly which tools it calls with what data."
      >
        <.toggle
          key="anthropic.verbose"
          scope={@scope}
          checked={setting_val(@effective, "anthropic.verbose") == true}
        />
      </.row>
      <.row
        label="Include partial messages"
        help="--include-partial-messages"
        description="With streaming output, includes in-progress fragments of Claude's response as they are generated."
      >
        <.toggle
          key="anthropic.include_partial_messages"
          scope={@scope}
          checked={setting_val(@effective, "anthropic.include_partial_messages") == true}
        />
      </.row>
    </.section>
    """
  end

  attr :scope, :string, required: true
  attr :effective, :map, default: %{}

  defp anthropic_safety(assigns) do
    ~H"""
    <.section title="Safety">
      <.row
        label="No session persistence"
        help="--no-session-persistence"
        description="Prevents the session from being saved to local history | cannot be resumed or rewound later."
      >
        <.toggle
          key="anthropic.no_session_persistence"
          scope={@scope}
          checked={setting_val(@effective, "anthropic.no_session_persistence") == true}
        />
      </.row>
      <.row
        label="Chrome integration"
        help="--chrome / --no-chrome"
        description="Enables or disables Claude's ability to control a browser for web testing or data extraction."
      >
        <.select_input
          key="anthropic.chrome"
          scope={@scope}
          value={setting_val(@effective, "anthropic.chrome") || ""}
          options={["", "on", "off"]}
        />
      </.row>
      <.row
        label="OS sandbox isolation"
        help="--sandbox"
        description="Enforces strict OS-level boundaries on the Bash tool | limits which files Claude can read/write and which sites it can visit."
      >
        <.toggle
          key="anthropic.sandbox"
          scope={@scope}
          checked={setting_val(@effective, "anthropic.sandbox") == true}
        />
      </.row>
      <.row
        label="Dangerously skip permissions"
        help="--dangerously-skip-permissions"
        description="Bypasses all permission prompts so Claude works autonomously. Use only in isolated environments (Docker, VMs) | Claude could delete files or run dangerous commands."
      >
        <.toggle
          key="anthropic.dangerously_skip_permissions"
          scope={@scope}
          checked={setting_val(@effective, "anthropic.dangerously_skip_permissions") == true}
        />
      </.row>
    </.section>
    """
  end

  # -- CODEX / OPENAI FLAGS --------------------------------------------------

  attr :scope, :string, required: true
  attr :effective, :map, default: %{}

  defp openai_section(assigns) do
    ~H"""
    <.section title="Execution">
      <.row label="Ask for approval" help="--ask-for-approval / -a">
        <.select_input
          key="openai.ask_for_approval"
          scope={@scope}
          value={setting_val(@effective, "openai.ask_for_approval") || "never"}
          options={["never", "on-failure", "on-request", "untrusted"]}
        />
      </.row>
      <.row label="Sandbox" help="--sandbox / -s">
        <.select_input
          key="openai.sandbox"
          scope={@scope}
          value={setting_val(@effective, "openai.sandbox") || "workspace-write"}
          options={["read-only", "workspace-write", "danger-full-access"]}
        />
      </.row>
      <.row label="Full auto" help="--full-auto (local automation shortcut)">
        <.toggle
          key="openai.full_auto"
          scope={@scope}
          checked={setting_val(@effective, "openai.full_auto") == true}
        />
      </.row>
      <.row
        label="Dangerously bypass approvals & sandbox"
        help="--dangerously-bypass-approvals-and-sandbox | for isolated VMs / CI only"
      >
        <.toggle
          key="openai.dangerously_bypass_approvals_and_sandbox"
          scope={@scope}
          checked={setting_val(@effective, "openai.dangerously_bypass_approvals_and_sandbox") == true}
        />
      </.row>
    </.section>
    """
  end

  # -- primitives ------------------------------------------------------------

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <div class="px-4 py-3">
      <h4 class="mb-2 text-mini font-medium uppercase tracking-normal text-base-content/50">
        {@title}
      </h4>
      <div class="flex flex-col divide-y divide-base-content/5">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp divider(assigns) do
    ~H"""
    <div class="border-t border-base-content/5"></div>
    """
  end

  attr :label, :string, required: true
  attr :help, :string, default: nil
  attr :description, :string, default: nil
  attr :override, :boolean, default: false
  slot :inner_block, required: true

  defp row(assigns) do
    ~H"""
    <div class="flex items-start justify-between py-3 gap-4">
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-1.5 text-message text-base-content/90">
          {@label}
          <span :if={@help} class="text-mini font-mono text-base-content/40">{@help}</span>
          <span
            :if={@override}
            class="inline-block h-1.5 w-1.5 rounded-full bg-warning"
            title="Overrides agent default"
          >
          </span>
        </div>
        <div :if={@description} class="text-mini text-base-content/55 mt-0.5 leading-snug max-w-md">
          {@description}
        </div>
      </div>
      <div class="flex items-center flex-shrink-0 pt-0.5">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :key, :string, required: true
  attr :scope, :string, required: true
  attr :checked, :boolean, default: false

  defp toggle(assigns) do
    ~H"""
    <input
      type="checkbox"
      id={"dm-setting-#{@key}"}
      class="toggle toggle-sm toggle-primary"
      checked={@checked}
      phx-click="dm_setting_update"
      phx-value-scope={@scope}
      phx-value-key={@key}
    />
    """
  end

  attr :key, :string, required: true
  attr :scope, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: ""
  attr :step, :string, default: "any"
  attr :min, :string, default: "0"

  defp num_input(assigns) do
    ~H"""
    <input
      type="number"
      id={"dm-setting-#{@key}"}
      step={@step}
      min={@min}
      value={@value}
      placeholder={@placeholder}
      phx-blur="dm_setting_update"
      phx-value-scope={@scope}
      phx-value-key={@key}
      class="input input-bordered input-sm w-28 text-message"
    />
    """
  end

  attr :key, :string, required: true
  attr :scope, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""

  defp text_input(assigns) do
    ~H"""
    <input
      type="text"
      id={"dm-setting-#{@key}"}
      value={@value}
      placeholder={@placeholder}
      phx-blur="dm_setting_update"
      phx-value-scope={@scope}
      phx-value-key={@key}
      class="input input-bordered input-sm w-56 text-message"
    />
    """
  end

  attr :key, :string, required: true
  attr :scope, :string, required: true
  attr :value, :string, default: ""

  defp text_area(assigns) do
    ~H"""
    <textarea
      id={"dm-setting-#{@key}"}
      rows="2"
      phx-blur="dm_setting_update"
      phx-value-scope={@scope}
      phx-value-key={@key}
      class="textarea textarea-bordered textarea-sm w-56 text-message font-mono"
    >{@value}</textarea>
    """
  end

  attr :key, :string, required: true
  attr :scope, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  defp select_input(assigns) do
    ~H"""
    <select
      id={"dm-setting-#{@key}"}
      class="select select-bordered select-sm w-56 text-message"
      phx-change="dm_setting_update"
      phx-value-scope={@scope}
      phx-value-key={@key}
    >
      <option :for={opt <- @options} value={opt} selected={opt == @value}>
        {if opt == "", do: "-", else: opt}
      </option>
    </select>
    """
  end

  defp setting_val(effective, dotted_key) do
    [section, key] = String.split(dotted_key, ".", parts: 2)
    get_in(effective, [section, key])
  end
end
