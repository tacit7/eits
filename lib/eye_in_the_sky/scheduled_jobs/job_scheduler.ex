defmodule EyeInTheSky.ScheduledJobs.JobScheduler do
  @moduledoc false
  import Ecto.Query, warn: false

  alias EyeInTheSky.Repo
  alias EyeInTheSky.ScheduledJobs.CronParser
  alias EyeInTheSky.ScheduledJobs.ScheduledJob

  defdelegate compute_next_run_at(schedule_type, schedule_value, from \\ nil, timezone \\ "Etc/UTC"),
    to: CronParser

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

end
