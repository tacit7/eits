defmodule EyeInTheSky.ScheduledJobs.JobScheduler do
  @moduledoc false
  import Ecto.Query, warn: false

  alias Crontab.CronExpression.Parser
  alias EyeInTheSky.Repo
  alias EyeInTheSky.ScheduledJobs.ScheduledJob
  alias EyeInTheSky.Utils.ToolHelpers

  def compute_next_run_at(schedule_type, schedule_value, from \\ nil, timezone \\ "Etc/UTC") do
    utc_now = from || NaiveDateTime.utc_now()

    case schedule_type do
      "interval" ->
        seconds = ToolHelpers.parse_int(schedule_value) || 0
        NaiveDateTime.add(utc_now, seconds) |> DateTime.from_naive!("Etc/UTC")

      "cron" ->
        next_cron_run_at(schedule_value, utc_now, timezone)
    end
  end

  def due_jobs do
    now = DateTime.utc_now()

    from(j in ScheduledJob,
      where: j.enabled == 1 and not is_nil(j.next_run_at) and j.next_run_at <= ^now
    )
    |> Repo.all()
  end

  def mark_job_executed(job) do
    now = NaiveDateTime.utc_now()

    next =
      compute_next_run_at(job.schedule_type, job.schedule_value, now, job.timezone || "Etc/UTC")

    fields = %{
      last_run_at: DateTime.utc_now(),
      next_run_at: next,
      run_count: (job.run_count || 0) + 1,
      updated_at: DateTime.utc_now()
    }

    job |> ScheduledJob.changeset(fields) |> Repo.update()
  end

  defp next_cron_run_at(schedule_value, utc_now, timezone) do
    case Parser.parse(schedule_value) do
      {:ok, parsed} ->
        local_now = utc_to_local(utc_now, timezone)

        case Crontab.Scheduler.get_next_run_date(parsed, local_now) do
          {:ok, next_local} -> local_to_utc(next_local, timezone) |> DateTime.from_naive!("Etc/UTC")
          _ -> nil
        end

      {:error, _} ->
        nil
    end
  end

  defp utc_to_local(naive_utc, "Etc/UTC"), do: naive_utc

  defp utc_to_local(naive_utc, timezone) do
    naive_utc
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_naive()
  end

  defp local_to_utc(naive_local, "Etc/UTC"), do: naive_local

  defp local_to_utc(naive_local, timezone) do
    naive_local
    |> DateTime.from_naive!(timezone)
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
  end
end
