defmodule EyeInTheSkyWebWeb.Live.Shared.JobsHelpers do
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import EyeInTheSkyWebWeb.ControllerHelpers, only: [parse_int: 2]

  alias EyeInTheSkyWeb.ScheduledJobs

  # ---------------------------------------------------------------------------
  # Event handler helpers — return {:noreply, socket}
  # Each LiveView delegates its handle_event/3 to these.
  # ---------------------------------------------------------------------------

  def handle_cancel_form(_params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_change_job_type(%{"job" => %{"job_type" => jt}}, socket) do
    {:noreply, assign(socket, :form_job_type, jt)}
  end

  def handle_change_schedule_type(%{"job" => %{"schedule_type" => st}}, socket) do
    {:noreply, assign(socket, :form_schedule_type, st)}
  end

  def handle_toggle_claude_drawer(_params, socket) do
    {:noreply, assign(socket, :show_claude_drawer, !socket.assigns.show_claude_drawer)}
  end

  def handle_claude_model_changed(%{"model" => model}, socket) do
    {:noreply, assign(socket, :claude_model, model)}
  end

  def handle_expand_job(%{"id" => id}, socket) do
    job_id = String.to_integer(id)

    if socket.assigns.expanded_job_id == job_id do
      {:noreply, assign(socket, expanded_job_id: nil, runs: [])}
    else
      runs = ScheduledJobs.list_runs_for_job(job_id)
      {:noreply, assign(socket, expanded_job_id: job_id, runs: runs)}
    end
  end

  def handle_run_now(%{"id" => id}, socket) do
    ScheduledJobs.run_now(String.to_integer(id))
    {:noreply, put_flash(socket, :info, "Job triggered")}
  end

  # ---------------------------------------------------------------------------
  # Pure helper functions — used in render templates and event handlers
  # ---------------------------------------------------------------------------

  def build_config(params) do
    case params["job_type"] do
      "spawn_agent" ->
        %{
          "instructions" => params["config_instructions"] || "",
          "model" => params["config_model"] || "sonnet",
          "project_path" => params["config_project_path"] || "",
          "description" => params["config_description"] || ""
        }

      "shell_command" ->
        %{
          "command" => params["config_command"] || "",
          "working_dir" => params["config_working_dir"] || "",
          "timeout_ms" => parse_int(params["config_timeout_ms"], 30_000)
        }

      "mix_task" ->
        args =
          (params["config_args"] || "")
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)

        %{
          "task" => params["config_task"] || "",
          "args" => args,
          "project_path" => params["config_project_path"] || ""
        }

      _ ->
        %{}
    end
  end

  def format_time(nil), do: "-"

  def format_time(iso) when is_binary(iso) do
    case NaiveDateTime.from_iso8601(String.replace(iso, "Z", "")) do
      {:ok, dt} -> Calendar.strftime(dt, "%m/%d %H:%M")
      _ -> iso
    end
  end

  def type_badge_class("spawn_agent"), do: "badge-primary"
  def type_badge_class("shell_command"), do: "badge-warning"
  def type_badge_class("mix_task"), do: "badge-accent"
  def type_badge_class(_), do: "badge-ghost"

  def type_label("spawn_agent"), do: "Agent"
  def type_label("shell_command"), do: "Shell"
  def type_label("mix_task"), do: "Mix"
  def type_label(t), do: t

  def status_badge_class("running"), do: "badge-info"
  def status_badge_class("completed"), do: "badge-success"
  def status_badge_class("failed"), do: "badge-error"
  def status_badge_class(_), do: "badge-ghost"

  def cfg(config, key) do
    case config do
      %{^key => val} when is_binary(val) -> val
      %{^key => val} when is_list(val) -> Enum.join(val, ", ")
      %{^key => val} -> to_string(val)
      _ -> ""
    end
  end
end
