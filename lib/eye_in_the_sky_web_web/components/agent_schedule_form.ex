defmodule EyeInTheSkyWebWeb.Components.AgentScheduleForm do
  @moduledoc """
  Scheduling form for agent prompts.
  Drawer on mobile (< sm), centered modal on desktop (>= sm). CSS-only, no JS.
  """

  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents

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
          <.form_body prompt={@prompt} job={@job} projects={@projects} context_project_id={@context_project_id} />
        </div>
      </div>

      <%!-- Desktop modal --%>
      <div class="hidden sm:flex fixed inset-0 z-50 items-center justify-center">
        <div class="bg-base-100 rounded-xl shadow-2xl w-full max-w-md p-6 border border-base-300">
          <.form_body prompt={@prompt} job={@job} projects={@projects} context_project_id={@context_project_id} />
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
      case Jason.decode((assigns.job && assigns.job.config) || "{}") do
        {:ok, m} -> m
        _ -> %{}
      end

    assigns =
      assigns
      |> assign(:editing, assigns.job != nil)
      |> assign(:schedule_type, (assigns.job && assigns.job.schedule_type) || "cron")
      |> assign(:schedule_value, (assigns.job && assigns.job.schedule_value) || "")
      |> assign(:model, Map.get(config, "model", "sonnet"))

    ~H"""
    <div class="flex items-start justify-between mb-4">
      <div>
        <h2 class="text-base font-semibold">{if @editing, do: "Edit Schedule", else: "Schedule Agent"}</h2>
        <p class="text-xs text-base-content/50 mt-0.5">{@prompt.name}</p>
        <p class="text-xs text-base-content/40 mt-1 italic">Instructions captured at time of scheduling</p>
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
            <option value="haiku" selected={@model == "haiku"}>Haiku</option>
            <option value="sonnet" selected={@model in ["sonnet", ""]}>Sonnet</option>
            <option value="opus" selected={@model == "opus"}>Opus</option>
          </select>
        </div>
      </div>

      <div class="form-control">
        <label class="label">
          <span class="label-text text-xs">
            {if @schedule_type == "cron", do: "Cron Expression (UTC)", else: "Interval (seconds)"}
          </span>
        </label>
        <input
          type="text"
          name="schedule[schedule_value]"
          value={@schedule_value}
          placeholder={if @schedule_type == "cron", do: "0 5 * * *", else: "3600"}
          class="input input-bordered input-sm w-full font-mono"
          required
        />
      </div>

      <div class="form-control">
        <label class="label"><span class="label-text text-xs">Project (optional override)</span></label>
        <select name="schedule[project_override_id]" class="select select-bordered select-sm w-full">
          <option value="">— use prompt default —</option>
          <%= for p <- @projects do %>
            <option
              value={p.id}
              selected={
                is_nil(@prompt.project_id) &&
                @context_project_id &&
                @context_project_id == p.id
              }
            >
              {p.name}
            </option>
          <% end %>
        </select>
      </div>

      <div class="flex justify-end gap-2 pt-2">
        <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_schedule">Cancel</button>
        <button type="submit" class="btn btn-primary btn-sm">Save Schedule</button>
      </div>
    </form>
    """
  end
end
