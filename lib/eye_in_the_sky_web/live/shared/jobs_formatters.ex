defmodule EyeInTheSkyWeb.Live.Shared.JobsFormatters do
  @moduledoc false
  alias EyeInTheSky.ScheduledJobs.ScheduleDescription

  # ---------------------------------------------------------------------------
  # Schedule formatting
  # ---------------------------------------------------------------------------

  # Single source of truth lives in ScheduleDescription (domain layer), shared
  # with the job create/edit form preview so the table and form can never disagree.
  defdelegate format_schedule(job), to: ScheduleDescription, as: :describe

  # ---------------------------------------------------------------------------
  # Timezone
  # ---------------------------------------------------------------------------

  def system_timezone do
    System.get_env("TZ") || detect_macos_timezone() || "UTC"
  end

  defp detect_macos_timezone do
    case System.cmd("readlink", ["/etc/localtime"], stderr_to_stdout: true) do
      {path, 0} ->
        case Regex.run(~r"zoneinfo/(.+)$", String.trim(path)) do
          [_, tz] -> tz
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Badge and display helpers
  # ---------------------------------------------------------------------------

  def type_badge_class("spawn_agent"), do: "badge-primary"
  def type_badge_class("mix_task"), do: "badge-accent"
  def type_badge_class(_), do: "badge-ghost"

  def type_label("spawn_agent"), do: "Agent"
  def type_label("mix_task"), do: "Mix"
  def type_label(t), do: t

  def status_badge_class("running"), do: "badge-info"
  def status_badge_class("completed"), do: "badge-success"
  def status_badge_class("failed"), do: "badge-error"
  def status_badge_class(_), do: "badge-ghost"

  # Returns :disabled | :running | :failed | :healthy for a job row.
  def job_row_state(job, running_ids, last_run_map) do
    cond do
      job.enabled != true -> :disabled
      MapSet.member?(running_ids, job.id) -> :running
      Map.get(last_run_map, job.id) == "failed" -> :failed
      true -> :healthy
    end
  end

  def cfg(config, key) do
    case config do
      %{^key => val} when is_binary(val) -> val
      %{^key => val} when is_list(val) -> Enum.join(val, ", ")
      %{^key => val} -> to_string(val)
      _ -> ""
    end
  end
end
