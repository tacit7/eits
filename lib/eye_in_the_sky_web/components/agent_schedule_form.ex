defmodule EyeInTheSkyWeb.Components.AgentScheduleForm do
  @moduledoc """
  Scheduling form for agent prompts.
  Drawer on mobile (< sm), centered modal on desktop (>= sm). CSS-only, no JS.
  """

  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [claude_models: 0]
  import EyeInTheSkyWeb.Live.Shared.JobsFormatters, only: [system_timezone: 0]

  attr :show, :boolean, required: true
  attr :prompt, :any, required: true
  attr :job, :any, default: nil
  attr :projects, :list, required: true
  attr :context_project_id, :any, default: nil

  def agent_schedule_form(assigns) do
    ~H"""
    <%= if @show do %>
      <div class="fixed inset-0 z-40 bg-black/30" phx-click="cancel_schedule"></div>

      <%!-- Mobile drawer --%>
      <div class="sm:hidden fixed inset-y-0 right-0 z-50 w-full max-w-sm bg-base-100 shadow-xl overflow-y-auto">
        <div class="p-5">
          <.form_body
            prompt={@prompt}
            job={@job}
            projects={@projects}
            context_project_id={@context_project_id}
          />
        </div>
      </div>

      <%!-- Desktop modal --%>
      <div class="hidden sm:flex fixed inset-0 z-50 items-center justify-center">
        <div class="bg-base-100 rounded-xl shadow-2xl w-full max-w-lg p-6 border border-base-300 max-h-[90vh] overflow-y-auto">
          <.form_body
            prompt={@prompt}
            job={@job}
            projects={@projects}
            context_project_id={@context_project_id}
          />
        </div>
      </div>
    <% end %>
    """
  end

  attr :prompt, :any, required: true
  attr :job, :any, default: nil
  attr :projects, :list, required: true
  attr :context_project_id, :any, default: nil

  defp form_body(assigns) do
    config =
      case Jason.decode((if assigns.job, do: assigns.job.config) || "{}") do
        {:ok, m} -> m
        _ -> %{}
      end

    assigns =
      assigns
      |> assign(:editing, not is_nil(assigns.job))
      |> assign(:schedule_type, (if assigns.job, do: assigns.job.schedule_type) || "cron")
      |> assign(:schedule_value, (if assigns.job, do: assigns.job.schedule_value) || "")
      |> assign(:model, Map.get(config, "model", "sonnet"))
      |> assign(:timezone, (if assigns.job, do: assigns.job.timezone) || system_timezone())
      |> assign(:config, config)

    ~H"""
    <div class="flex items-start justify-between mb-4">
      <div>
        <h2 class="text-base font-semibold">
          {if @editing, do: "Edit Schedule", else: "Schedule Agent"}
        </h2>
        <p class="text-xs text-base-content/50 mt-0.5">{@prompt.name}</p>
        <p class="text-xs text-base-content/40 mt-1 italic">
          Instructions captured at time of scheduling
        </p>
      </div>
      <button class="btn btn-ghost btn-sm btn-square" phx-click="cancel_schedule">
        <.icon name="hero-x-mark" class="w-4 h-4" />
      </button>
    </div>

    <form phx-submit="save_schedule" class="space-y-4">
      <input type="hidden" name="schedule[prompt_id]" value={@prompt.id} />
      <%= if @job do %>
        <input type="hidden" name="schedule[job_id]" value={@job.id} />
      <% end %>

      <.schedule_type_fields
        schedule_type={@schedule_type}
        schedule_value={@schedule_value}
        model={@model}
      />

      <%= if @schedule_type == "cron" do %>
        <.cron_reference />
        <.timezone_picker timezone={@timezone} />
      <% end %>

      <div class="form-control">
        <label class="label">
          <span class="label-text text-xs">Project (optional override)</span>
        </label>
        <select name="schedule[project_override_id]" class="select select-bordered select-sm w-full">
          <option value="">— use prompt default —</option>
          <%= for p <- @projects do %>
            <option
              value={p.id}
              selected={
                is_nil(@prompt.project_id) &&
                  not is_nil(@context_project_id) &&
                  @context_project_id == p.id
              }
            >
              {p.name}
            </option>
          <% end %>
        </select>
      </div>

      <.advanced_cli_flags config={@config} />

      <div class="flex justify-end gap-2 pt-2">
        <button type="button" class="btn btn-ghost btn-sm min-h-[44px]" phx-click="cancel_schedule">Cancel</button>
        <button type="submit" class="btn btn-primary btn-sm min-h-[44px]">Save Schedule</button>
      </div>
    </form>
    """
  end

  # ---------------------------------------------------------------------------
  # Sub-components
  # ---------------------------------------------------------------------------

  attr :schedule_type, :string, required: true
  attr :schedule_value, :string, required: true
  attr :model, :string, required: true

  defp schedule_type_fields(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-3">
      <div class="form-control">
        <label class="label"><span class="label-text text-xs">Schedule Type</span></label>
        <select name="schedule[schedule_type]" class="select select-bordered select-sm w-full">
          <option value="cron" selected={@schedule_type == "cron"}>Cron</option>
          <option value="interval" selected={@schedule_type == "interval"}>Interval</option>
        </select>
      </div>
      <div class="form-control">
        <label class="label"><span class="label-text text-xs">Model</span></label>
        <select name="schedule[model]" class="select select-bordered select-sm w-full">
          <%= for {value, label} <- claude_models() do %>
            <option value={value} selected={@model == value}>{label}</option>
          <% end %>
        </select>
      </div>
    </div>

    <div class="form-control">
      <label class="label">
        <span class="label-text text-xs">
          {if @schedule_type == "cron", do: "Cron Expression", else: "Interval (seconds)"}
        </span>
      </label>
      <input
        type="text"
        name="schedule[schedule_value]"
        value={@schedule_value}
        placeholder={if @schedule_type == "cron", do: "0 9 * * *", else: "3600"}
        class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
        required
      />
    </div>
    """
  end

  defp cron_reference(assigns) do
    ~H"""
    <div class="collapse collapse-arrow bg-base-200 rounded-lg">
      <input type="checkbox" class="min-h-0" />
      <div class="collapse-title min-h-0 py-2 px-3 flex items-center gap-1.5 text-xs text-base-content/60">
        <.icon name="hero-question-mark-circle" class="w-3.5 h-3.5" /> Cron syntax reference
      </div>
      <div class="collapse-content px-3 pb-3">
        <table class="table table-xs w-full">
          <thead>
            <tr class="text-base-content/40">
              <th class="pl-0">Position</th>
              <th>Values</th>
              <th class="pr-0">Specials</th>
            </tr>
          </thead>
          <tbody class="text-xs">
            <tr>
              <td class="pl-0 font-medium">Minute</td>
              <td>0 - 59</td>
              <td class="pr-0 font-mono text-base-content/50">* , - /</td>
            </tr>
            <tr>
              <td class="pl-0 font-medium">Hour</td>
              <td>0 - 23</td>
              <td class="pr-0 font-mono text-base-content/50">* , - /</td>
            </tr>
            <tr>
              <td class="pl-0 font-medium">Day of month</td>
              <td>1 - 31</td>
              <td class="pr-0 font-mono text-base-content/50">* , - /</td>
            </tr>
            <tr>
              <td class="pl-0 font-medium">Month</td>
              <td>1 - 12</td>
              <td class="pr-0 font-mono text-base-content/50">* , - /</td>
            </tr>
            <tr>
              <td class="pl-0 font-medium">Day of week</td>
              <td>0 - 6 (Sun=0)</td>
              <td class="pr-0 font-mono text-base-content/50">* , - /</td>
            </tr>
          </tbody>
        </table>
        <div class="divider my-1"></div>
        <p class="text-xs font-medium text-base-content/50 mb-1">Examples</p>
        <div class="grid grid-cols-2 gap-x-3 gap-y-0.5 text-xs">
          <code class="font-mono text-primary">0 9 * * *</code><span class="text-base-content/50">Daily at 9:00 AM</span>
          <code class="font-mono text-primary">*/15 * * * *</code><span class="text-base-content/50">Every 15 minutes</span>
          <code class="font-mono text-primary">0 9 * * 1-5</code><span class="text-base-content/50">Weekdays at 9 AM</span>
          <code class="font-mono text-primary">0 0 1 * *</code><span class="text-base-content/50">1st of each month</span>
          <code class="font-mono text-primary">30 */2 * * *</code><span class="text-base-content/50">Every 2 hours at :30</span>
          <code class="font-mono text-primary">0 8-17 * * *</code><span class="text-base-content/50">Hourly, 8 AM - 5 PM</span>
        </div>
      </div>
    </div>
    """
  end

  @common_timezones [
    "Etc/UTC",
    "US/Eastern",
    "US/Central",
    "US/Mountain",
    "US/Pacific",
    "US/Hawaii",
    "Europe/London",
    "Europe/Paris",
    "Europe/Berlin",
    "Asia/Tokyo",
    "Asia/Shanghai",
    "Asia/Kolkata",
    "Australia/Sydney",
    "America/Sao_Paulo",
    "America/Mexico_City"
  ]

  attr :timezone, :string, required: true

  defp timezone_picker(assigns) do
    all =
      if assigns.timezone in @common_timezones,
        do: @common_timezones,
        else: [assigns.timezone | @common_timezones]

    assigns = assign(assigns, :timezones, all)

    ~H"""
    <div class="form-control">
      <label class="label"><span class="label-text text-xs">Timezone</span></label>
      <select name="schedule[timezone]" class="select select-bordered select-sm w-full">
        <%= for tz <- @timezones do %>
          <option value={tz} selected={tz == @timezone}>{tz}</option>
        <% end %>
      </select>
    </div>
    """
  end

  attr :config, :map, required: true

  defp advanced_cli_flags(assigns) do
    %{
      "max_budget_usd" => max_budget_usd,
      "max_turns" => max_turns,
      "fallback_model" => fallback_model,
      "output_format" => output_format,
      "permission_mode" => permission_mode,
      "allowed_tools" => allowed_tools,
      "add_dir" => add_dir,
      "mcp_config" => mcp_config,
      "plugin_dir" => plugin_dir,
      "settings_file" => settings_file,
      "skip_permissions" => skip_permissions,
      "chrome" => chrome,
      "sandbox" => sandbox
    } = Map.merge(
      %{
        "max_budget_usd" => "",
        "max_turns" => "",
        "fallback_model" => "",
        "output_format" => "",
        "permission_mode" => "",
        "allowed_tools" => "",
        "add_dir" => "",
        "mcp_config" => "",
        "plugin_dir" => "",
        "settings_file" => "",
        "skip_permissions" => true,
        "chrome" => false,
        "sandbox" => false
      },
      assigns.config
    )

    assigns =
      assigns
      |> assign(:max_budget_usd, max_budget_usd)
      |> assign(:max_turns, max_turns)
      |> assign(:fallback_model, fallback_model)
      |> assign(:output_format, output_format)
      |> assign(:permission_mode, permission_mode)
      |> assign(:allowed_tools, allowed_tools)
      |> assign(:add_dir, add_dir)
      |> assign(:mcp_config, mcp_config)
      |> assign(:plugin_dir, plugin_dir)
      |> assign(:settings_file, settings_file)
      |> assign(:skip_permissions, skip_permissions)
      |> assign(:chrome, chrome)
      |> assign(:sandbox, sandbox)

    ~H"""
    <div class="collapse collapse-arrow bg-base-200 rounded-lg">
      <input type="checkbox" class="min-h-0" />
      <div class="collapse-title min-h-0 py-2.5 px-3 flex items-center gap-1.5 text-xs font-medium text-base-content/60">
        <.icon name="hero-adjustments-horizontal" class="w-3.5 h-3.5" /> Advanced CLI Flags
      </div>
      <div class="collapse-content px-3 pb-3 space-y-3">

        <div class="grid grid-cols-2 gap-3">
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Max Budget (USD)</span></label>
            <input
              type="number"
              name="schedule[max_budget_usd]"
              value={@max_budget_usd}
              placeholder="e.g. 5.00"
              step="0.01"
              min="0"
              class="input input-bordered input-sm w-full font-mono min-h-[44px]"
            />
          </div>
          <div class="form-control">
            <label class="label">
              <span class="label-text text-xs">Max Turns</span>
              <span class="label-text-alt text-base-content/40 font-mono text-xs">--max-turns</span>
            </label>
            <input
              type="number"
              name="schedule[max_turns]"
              value={@max_turns}
              placeholder="e.g. 25"
              min="1"
              class="input input-bordered input-sm w-full font-mono min-h-[44px]"
            />
          </div>
        </div>

        <div class="grid grid-cols-2 gap-3">
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Fallback Model</span></label>
            <select name="schedule[fallback_model]" class="select select-bordered select-sm w-full">
              <option value="" selected={@fallback_model == ""}>None</option>
              <%= for {value, label} <- claude_models() do %>
                <option value={value} selected={@fallback_model == value}>{label}</option>
              <% end %>
            </select>
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Output Format</span></label>
            <select name="schedule[output_format]" class="select select-bordered select-sm w-full">
              <option value="" selected={@output_format == ""}>Default</option>
              <option value="text" selected={@output_format == "text"}>Text</option>
              <option value="json" selected={@output_format == "json"}>JSON</option>
              <option value="stream-json" selected={@output_format == "stream-json"}>Stream JSON</option>
            </select>
          </div>
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">Permission Mode</span>
            <span class="label-text-alt text-base-content/40 font-mono text-xs">--permission-mode</span>
          </label>
          <select name="schedule[permission_mode]" class="select select-bordered select-sm w-full">
            <option value="" selected={@permission_mode == ""}>Default</option>
            <option value="acceptEdits" selected={@permission_mode == "acceptEdits"}>acceptEdits — auto-accept file edits</option>
            <option value="bypassPermissions" selected={@permission_mode == "bypassPermissions"}>bypassPermissions — skip all prompts</option>
            <option value="dontAsk" selected={@permission_mode == "dontAsk"}>dontAsk — never ask</option>
            <option value="plan" selected={@permission_mode == "plan"}>plan — read-only</option>
          </select>
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text text-xs">Allowed Tools</span></label>
          <input
            type="text"
            name="schedule[allowed_tools]"
            value={@allowed_tools}
            placeholder="e.g. Bash,Read,Edit,Write,Grep,Glob"
            class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
          />
          <label class="label">
            <span class="label-text-alt text-base-content/40">Comma-separated. Supports wildcards: Bash(git *)</span>
          </label>
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">Add Directory</span>
            <span class="label-text-alt text-base-content/40 font-mono text-xs">--add-dir</span>
          </label>
          <input
            type="text"
            name="schedule[add_dir]"
            value={@add_dir}
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
            name="schedule[mcp_config]"
            value={@mcp_config}
            placeholder="./mcp-servers.json"
            class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
          />
        </div>

        <div class="grid grid-cols-2 gap-3">
          <div class="form-control">
            <label class="label">
              <span class="label-text text-xs">Plugin Directory</span>
              <span class="label-text-alt text-base-content/40 font-mono text-xs">--plugin-dir</span>
            </label>
            <input
              type="text"
              name="schedule[plugin_dir]"
              value={@plugin_dir}
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
              name="schedule[settings_file]"
              value={@settings_file}
              placeholder="./settings.json"
              class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
            />
          </div>
        </div>

        <div class="flex flex-col gap-1 pt-1">
          <label class="label cursor-pointer justify-start gap-2 py-1">
            <input
              type="checkbox"
              name="schedule[skip_permissions]"
              value="true"
              checked={@skip_permissions}
              class="checkbox checkbox-sm checkbox-primary"
            />
            <span class="label-text text-xs">
              Skip permissions
              <span class="font-mono text-base-content/40 text-xs ml-1">--dangerously-skip-permissions</span>
            </span>
          </label>
          <label class="label cursor-pointer justify-start gap-2 py-1">
            <input
              type="checkbox"
              name="schedule[chrome]"
              value="true"
              checked={@chrome}
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
              name="schedule[sandbox]"
              value="true"
              checked={@sandbox}
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
    """
  end
end
