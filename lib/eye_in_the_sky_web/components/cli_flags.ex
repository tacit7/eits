defmodule EyeInTheSkyWeb.Components.CliFlags do
  @moduledoc """
  Shared CLI flag fields used by both NewSessionModal and AgentScheduleForm.
  """

  use Phoenix.Component

  attr :scope, :string, default: ""
  attr :add_dir, :string, default: nil
  attr :mcp_config, :string, default: nil
  attr :plugin_dir, :string, default: nil
  attr :settings_file, :string, default: nil
  attr :compact_paths, :boolean,
    default: false,
    doc: "When true, wraps plugin_dir + settings_file in a 2-column grid (matches agent_schedule_form layout)."

  def path_fields(assigns) do
    ~H"""
    <div class="form-control">
      <label class="label">
        <span class="label-text text-xs">Add Directory</span>
        <span class="label-text-alt text-base-content/40 font-mono text-xs">--add-dir</span>
      </label>
      <input
        type="text"
        name={field_name(@scope, "add_dir")}
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
        name={field_name(@scope, "mcp_config")}
        value={@mcp_config}
        placeholder="./mcp-servers.json"
        class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
      />
    </div>

    <div class={if @compact_paths, do: "grid grid-cols-2 gap-3", else: "contents"}>
      <div class="form-control">
        <label class="label">
          <span class="label-text text-xs">Plugin Directory</span>
          <span class="label-text-alt text-base-content/40 font-mono text-xs">--plugin-dir</span>
        </label>
        <input
          type="text"
          name={field_name(@scope, "plugin_dir")}
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
          name={field_name(@scope, "settings_file")}
          value={@settings_file}
          placeholder="./settings.json"
          class="input input-bordered input-sm w-full font-mono text-base min-h-[44px]"
        />
      </div>
    </div>
    """
  end

  attr :scope, :string, default: ""
  attr :skip_permissions, :boolean, default: nil
  attr :chrome, :boolean, default: false
  attr :sandbox, :boolean, default: false

  def boolean_flags(assigns) do
    ~H"""
    <div class="flex flex-col gap-1 pt-1">
      <label :if={@skip_permissions != nil} class="label cursor-pointer justify-start gap-2 py-1">
        <input
          type="checkbox"
          name={field_name(@scope, "skip_permissions")}
          value="true"
          checked={@skip_permissions}
          class="checkbox checkbox-sm checkbox-primary"
        />
        <span class="label-text text-xs">
          Skip permissions
          <span class="font-mono text-base-content/40 text-xs ml-1">
            --dangerously-skip-permissions
          </span>
        </span>
      </label>
      <label class="label cursor-pointer justify-start gap-2 py-1">
        <input
          type="checkbox"
          name={field_name(@scope, "chrome")}
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
          name={field_name(@scope, "sandbox")}
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
    """
  end

  defp field_name("", field), do: field
  defp field_name(scope, field), do: "#{scope}[#{field}]"
end
