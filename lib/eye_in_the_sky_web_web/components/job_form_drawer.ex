defmodule EyeInTheSkyWebWeb.Components.JobFormDrawer do
  @moduledoc """
  Shared job creation/editing form drawer component.
  Stateless — parent LiveView retains all state and handles all events.
  """

  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents
  import EyeInTheSkyWebWeb.Live.Shared.JobsHelpers, only: [cfg: 2]

  @common_timezones [
    "Etc/UTC",
    "US/Eastern",
    "US/Central",
    "US/Mountain",
    "US/Pacific",
    "US/Alaska",
    "US/Hawaii",
    "Europe/London",
    "Europe/Paris",
    "Europe/Berlin",
    "Asia/Tokyo",
    "Asia/Shanghai",
    "Asia/Kolkata",
    "Australia/Sydney",
    "Pacific/Auckland"
  ]

  defp common_timezones, do: @common_timezones

  attr :show, :boolean, required: true
  attr :editing_job, :any, default: nil
  attr :form, :any, required: true
  attr :form_job_type, :string, required: true
  attr :form_schedule_type, :string, required: true
  attr :form_config, :map, required: true
  attr :project_id, :any, default: nil
  attr :project, :any, default: nil
  attr :form_scope, :string, default: nil
  attr :show_daily_digest, :boolean, default: false

  def job_form_drawer(assigns) do
    ~H"""
    <div>
      <div class={[
        "fixed inset-y-0 right-0 safe-inset-y z-50 w-full max-w-md bg-base-100 shadow-xl transform transition-transform duration-200 ease-in-out overflow-y-auto",
        if(@show, do: "translate-x-0", else: "translate-x-full")
      ]}>
        <div class="p-6">
          <div class="flex items-center justify-between mb-4">
            <div>
              <h2 class="text-lg font-semibold">
                {if @editing_job, do: "Edit Job", else: "New Job"}
              </h2>
              <%= if @project || @form_scope do %>
                <p class="text-xs text-base-content/50 mt-0.5">
                  {if @form_scope == "global",
                    do: "Global — runs across all projects",
                    else: "Project — scoped to #{@project && @project.name}"}
                </p>
              <% end %>
            </div>
            <button class="btn btn-ghost btn-sm btn-square" phx-click="cancel_form">
              <span class="sr-only">Close job form</span>
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>

          <.form
            for={@form}
            phx-submit="save_job"
            phx-change="change_job_type"
            class="space-y-4"
          >
            <%= if @project_id do %>
              <input type="hidden" name="job[project_id]" value={@project_id} />
            <% end %>

            <div class="form-control">
              <label class="label"><span class="label-text">Name</span></label>
              <input
                type="text"
                name="job[name]"
                value={@form[:name].value || ""}
                class={["input input-bordered w-full", @form[:name].errors != [] && "input-error"]}
              />
              <p :for={err <- @form[:name].errors} class="mt-1 text-xs text-error">
                {translate_error(err)}
              </p>
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Description</span></label>
              <input
                type="text"
                name="job[description]"
                value={@form[:description].value || ""}
                class="input input-bordered w-full"
              />
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Job Type</span></label>
                <select name="job[job_type]" class="select select-bordered w-full">
                  <option value="shell_command" selected={@form_job_type == "shell_command"}>
                    Shell Command
                  </option>
                  <option value="spawn_agent" selected={@form_job_type == "spawn_agent"}>
                    Spawn Agent
                  </option>
                  <option value="mix_task" selected={@form_job_type == "mix_task"}>Mix Task</option>
                  <%= if @show_daily_digest do %>
                    <option value="daily_digest" selected={@form_job_type == "daily_digest"}>
                      Daily Digest
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="form-control">
                <label class="label"><span class="label-text">Schedule Type</span></label>
                <select
                  name="job[schedule_type]"
                  class="select select-bordered w-full"
                  phx-change="change_schedule_type"
                >
                  <option value="interval" selected={@form_schedule_type == "interval"}>
                    Interval
                  </option>
                  <option value="cron" selected={@form_schedule_type == "cron"}>Cron</option>
                </select>
              </div>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text flex items-center gap-1">
                  {if @form_schedule_type == "interval",
                    do: "Interval (seconds)",
                    else: "Cron Expression"}
                  <%= if @form_schedule_type == "cron" do %>
                    <span
                      class="tooltip tooltip-bottom cursor-help"
                      data-tip="minute (0-59)  hour (0-23)  day-of-month (1-31)  month (1-12)  day-of-week (0-6, Sun=0)&#10;&#10;Examples:&#10;*/5 * * * *  = every 5 min&#10;0 9 * * 1-5  = 9 AM weekdays&#10;0 0 1 * *    = midnight, 1st of month"
                    >
                      <.icon name="hero-question-mark-circle" class="w-4 h-4 text-base-content/40" />
                    </span>
                  <% end %>
                </span>
              </label>
              <input
                type="text"
                name="job[schedule_value]"
                value={@form[:schedule_value].value || ""}
                placeholder={if @form_schedule_type == "interval", do: "60", else: "*/5 * * * *"}
                class={[
                  "input input-bordered w-full font-mono",
                  @form[:schedule_value].errors != [] && "input-error"
                ]}
              />
              <p :for={err <- @form[:schedule_value].errors} class="mt-1 text-xs text-error">
                {translate_error(err)}
              </p>
            </div>

            <%= if @form_schedule_type == "cron" do %>
              <div class="form-control">
                <label class="label"><span class="label-text">Timezone</span></label>
                <select name="job[timezone]" class="select select-bordered w-full">
                  <%= for tz <- common_timezones() do %>
                    <option
                      value={tz}
                      selected={@form[:timezone].value == tz}
                    >
                      {tz}
                    </option>
                  <% end %>
                </select>
              </div>
            <% end %>

            <%= if @form_job_type == "shell_command" do %>
              <div class="form-control">
                <label class="label"><span class="label-text">Command</span></label>
                <input
                  type="text"
                  name="job[config_command]"
                  value={cfg(@form_config, "command")}
                  class="input input-bordered w-full font-mono"
                  required
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Working Directory</span></label>
                <input
                  type="text"
                  name="job[config_working_dir]"
                  value={cfg(@form_config, "working_dir")}
                  class="input input-bordered w-full"
                />
              </div>
            <% end %>

            <%= if @form_job_type == "spawn_agent" do %>
              <div class="form-control">
                <label class="label"><span class="label-text">Instructions</span></label>
                <textarea
                  name="job[config_instructions]"
                  class="textarea textarea-bordered w-full"
                  rows="3"
                ><%= cfg(@form_config, "instructions") %></textarea>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="label-text">Model</span></label>
                  <select name="job[config_model]" class="select select-bordered w-full">
                    <option value="haiku" selected={cfg(@form_config, "model") == "haiku"}>
                      Haiku
                    </option>
                    <option value="sonnet" selected={cfg(@form_config, "model") in ["sonnet", ""]}>
                      Sonnet
                    </option>
                    <option value="opus" selected={cfg(@form_config, "model") == "opus"}>
                      Opus
                    </option>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Project Path</span></label>
                  <input
                    type="text"
                    name="job[config_project_path]"
                    value={cfg(@form_config, "project_path")}
                    class="input input-bordered w-full"
                  />
                </div>
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Agent Description</span></label>
                <input
                  type="text"
                  name="job[config_description]"
                  value={cfg(@form_config, "description")}
                  class="input input-bordered w-full"
                />
              </div>
            <% end %>

            <%= if @form_job_type == "mix_task" do %>
              <div class="form-control">
                <label class="label"><span class="label-text">Task Name</span></label>
                <input
                  type="text"
                  name="job[config_task]"
                  value={cfg(@form_config, "task")}
                  class="input input-bordered w-full font-mono"
                  required
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Arguments (comma-separated)</span>
                </label>
                <input
                  type="text"
                  name="job[config_args]"
                  value={cfg(@form_config, "args")}
                  class="input input-bordered w-full"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Project Path</span></label>
                <input
                  type="text"
                  name="job[config_project_path]"
                  value={cfg(@form_config, "project_path")}
                  class="input input-bordered w-full"
                />
              </div>
            <% end %>

            <div class="sticky bottom-0 bg-base-100 pt-4 pb-1 flex justify-end gap-2">
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_form">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
            </div>
          </.form>
        </div>
      </div>
      <%= if @show do %>
        <div class="fixed inset-0 z-40 bg-black/30" phx-click="cancel_form"></div>
      <% end %>
    </div>
    """
  end
end
