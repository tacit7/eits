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
      where: j.enabled and not is_nil(j.next_run_at) and j.next_run_at <= ^now
    )
    |> Repo.all()
  end

  @doc """
  Atomically claims a due job by advancing its next_run_at to a future sentinel.

  Uses the job's current next_run_at as an optimistic lock: the UPDATE only
  matches if no other poller has already claimed (and thus updated) the row.
  Returns :ok when claimed, {:error, :already_claimed} when another process got
  there first or the job was already advanced.
  """
  def claim_job(%ScheduledJob{id: id, next_run_at: next_run_at}) do
    # Push next_run_at one hour forward as a "claimed" sentinel so the job does
    # not re-appear as due even if mark_job_executed is delayed or fails.
    sentinel = DateTime.add(DateTime.utc_now(), 3600, :second)

    {count, _} =
      Repo.update_all(
        from(j in ScheduledJob,
          where: j.id == ^id and j.next_run_at == ^next_run_at
        ),
        set: [next_run_at: sentinel]
      )

    if count == 1, do: :ok, else: {:error, :already_claimed}
  end

  @doc """
  Reverts next_run_at to the original value, releasing a previously set claim
  sentinel. Call this when enqueueing fails after a successful claim so the job
  becomes due again on the next poll cycle instead of waiting out the sentinel.
  """
  def release_claim(%ScheduledJob{id: id}, original_next_run_at) do
    Repo.update_all(
      from(j in ScheduledJob, where: j.id == ^id),
      set: [next_run_at: original_next_run_at]
    )

    :ok
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
