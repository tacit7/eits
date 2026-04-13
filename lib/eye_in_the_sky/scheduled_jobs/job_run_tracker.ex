defmodule EyeInTheSky.ScheduledJobs.JobRunTracker do
  @moduledoc false
  import Ecto.Query, warn: false

  alias EyeInTheSky.Repo
  alias EyeInTheSky.ScheduledJobs.JobRun

  def list_running_job_ids do
    from(r in JobRun,
      where: r.status == "running",
      distinct: r.job_id,
      select: r.job_id
    )
    |> Repo.all()
  end

  def last_run_status_map do
    from(r in JobRun,
      where: r.status != "running",
      distinct: r.job_id,
      order_by: [asc: r.job_id, desc: r.started_at],
      select: {r.job_id, r.status}
    )
    |> Repo.all()
    |> Map.new()
  end

  def list_runs_for_job(job_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    from(r in JobRun,
      where: r.job_id == ^job_id,
      order_by: [desc: r.started_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def last_run_per_job([]), do: %{}

  def last_run_per_job(job_ids) when is_list(job_ids) do
    from(r in JobRun,
      where: r.job_id in ^job_ids,
      distinct: r.job_id,
      order_by: [asc: r.job_id, desc: r.started_at]
    )
    |> Repo.all()
    |> Map.new(fn r -> {r.job_id, r} end)
  end

  def record_run_start(job) do
    %JobRun{}
    |> JobRun.changeset(%{
      job_id: job.id,
      status: "running",
      started_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  def record_run_complete(run, status, opts \\ []) do
    result = Keyword.get(opts, :result)
    session_id = Keyword.get(opts, :session_id)

    run
    |> JobRun.changeset(%{
      status: status,
      completed_at: DateTime.utc_now(),
      result: result,
      session_id: session_id
    })
    |> Repo.update()
  end
end
