defmodule EyeInTheSky.ScheduledJobs do
  @moduledoc false
  import Ecto.Query, warn: false

  alias Crontab.CronExpression.Parser
  alias EyeInTheSky.Repo
  alias EyeInTheSky.ScheduledJobs.{JobRun, ScheduledJob}
  alias EyeInTheSky.Utils.ToolHelpers

  def list_jobs do
    from(j in ScheduledJob,
      order_by: [asc: j.origin, asc: j.name]
    )
    |> Repo.all()
  end

  def list_jobs_for_project(project_id) do
    from(j in ScheduledJob,
      where: j.project_id == ^project_id,
      order_by: [asc: j.origin, asc: j.name]
    )
    |> Repo.all()
  end

  def list_global_jobs do
    from(j in ScheduledJob,
      where: is_nil(j.project_id),
      order_by: [asc: j.origin, asc: j.name]
    )
    |> Repo.all()
  end

  def list_spawn_agent_jobs_by_prompt_ids(prompt_ids) when is_list(prompt_ids) do
    from(j in ScheduledJob, where: j.prompt_id in ^prompt_ids)
    |> Repo.all()
  end

  def list_filesystem_agent_jobs do
    from(j in ScheduledJob,
      where: j.job_type == "spawn_agent",
      where: is_nil(j.prompt_id),
      where: like(j.config, "%agent_file_id%")
    )
    |> Repo.all()
  end

  def list_orphaned_agent_jobs do
    from(j in ScheduledJob,
      join: p in assoc(j, :prompt),
      where: j.job_type == "spawn_agent",
      where: not is_nil(j.prompt_id),
      where: p.active == false
    )
    |> Repo.all()
  end

  def get_job!(id), do: Repo.get!(ScheduledJob, id)

  def get_job(id) do
    case Repo.get(ScheduledJob, id) do
      nil -> {:error, :not_found}
      job -> {:ok, job}
    end
  end

  def create_job(attrs) do
    now = DateTime.utc_now()

    attrs =
      attrs
      |> stringify_keys()
      |> Map.put_new("origin", "user")
      |> Map.put_new("created_at", now)
      |> Map.put_new("updated_at", now)
      |> maybe_encode_config()

    # For fs: agents (prompt_id is nil), check config for duplicate agent_file_id
    if fs_agent_already_scheduled?(attrs) do
      {:error, :already_scheduled}
    else
      create_job_insert(attrs)
    end
  end

  defp create_job_insert(attrs) do
    changeset = ScheduledJob.changeset(%ScheduledJob{}, attrs)

    case Repo.insert(changeset) do
      {:ok, job} ->
        next =
          compute_next_run_at(
            job.schedule_type,
            job.schedule_value,
            nil,
            job.timezone || "Etc/UTC"
          )

        update_job_fields(job, %{next_run_at: next})

      {:error, %Ecto.Changeset{} = cs} ->
        if Keyword.has_key?(cs.errors, :prompt_id),
          do: {:error, :already_scheduled},
          else: {:error, cs}
    end
  end

  def update_job(%ScheduledJob{} = job, attrs, caller_project_id \\ nil) do
    if authorized?(job, caller_project_id) do
      now = DateTime.utc_now()

      attrs =
        attrs
        |> stringify_keys()
        |> Map.delete("origin")
        |> Map.put("updated_at", now)
        |> maybe_encode_config()

      case job |> ScheduledJob.changeset(attrs) |> Repo.update() do
        {:ok, updated} -> maybe_recompute_next_run(updated, attrs)
        error -> error
      end
    else
      {:error, :unauthorized}
    end
  end

  defp maybe_recompute_next_run(updated, attrs) do
    if Map.has_key?(attrs, "next_run_at") do
      {:ok, updated}
    else
      next = compute_next_run_at(updated.schedule_type, updated.schedule_value, nil, updated.timezone || "Etc/UTC")
      update_job_fields(updated, %{next_run_at: next})
    end
  end

  def run_now(job_id, caller_project_id \\ nil) do
    with {:ok, job} <- get_job(job_id),
         :ok <- check_authorized(job, caller_project_id) do
      run_authorized_job(job)
    end
  end

  defp run_authorized_job(job) do
    case enqueue_job(job) do
      {:ok, _} = result ->
        mark_job_executed(job)
        result

      error ->
        error
    end
  end

  def delete_job(job, caller_project_id \\ nil)

  def delete_job(%ScheduledJob{origin: "system"}, _caller_project_id),
    do: {:error, :system_job}

  def delete_job(%ScheduledJob{} = job, caller_project_id) do
    if authorized?(job, caller_project_id) do
      Repo.delete(job)
    else
      {:error, :unauthorized}
    end
  end

  def toggle_job(%ScheduledJob{} = job, caller_project_id \\ nil) do
    if authorized?(job, caller_project_id) do
      new_enabled = if job.enabled == 1, do: 0, else: 1
      update_job_fields(job, %{enabled: new_enabled, updated_at: DateTime.utc_now()})
    else
      {:error, :unauthorized}
    end
  end

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

  @doc "Enqueue the appropriate Oban worker for a scheduled job."
  def enqueue_job(%ScheduledJob{} = job) do
    worker =
      case job.job_type do
        "shell_command" -> EyeInTheSky.Workers.ShellCommandWorker
        "spawn_agent" -> EyeInTheSky.Workers.SpawnAgentWorker
        "mix_task" -> EyeInTheSky.Workers.MixTaskWorker
        "daily_digest" -> EyeInTheSky.Workers.DailyDigestWorker
        "workable_task" -> EyeInTheSky.Workers.WorkableTaskWorker
      end

    %{"job_id" => job.id}
    |> worker.new(unique: [period: 30, fields: [:args, :worker], states: [:available, :scheduled, :executing]])
    |> Oban.insert()
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

    update_job_fields(job, %{
      last_run_at: DateTime.utc_now(),
      next_run_at: next,
      run_count: (job.run_count || 0) + 1,
      updated_at: DateTime.utc_now()
    })
  end

  def decode_config(%ScheduledJob{config: config}) when is_binary(config) do
    case Jason.decode(config) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  def decode_config(_), do: %{}

  def encode_config(map) when is_map(map), do: Jason.encode!(map)
  def encode_config(str) when is_binary(str), do: str

  def change_job(%ScheduledJob{} = job, attrs \\ %{}) do
    ScheduledJob.changeset(job, attrs)
  end

  # Private helpers

  # Returns true if the caller is allowed to mutate the job.
  # nil = overview/admin caller (no restriction).
  # integer = project-scoped caller: job must belong to that exact project.
  # Global jobs (job.project_id nil) are blocked from project-scoped callers.
  defp authorized?(_job, nil), do: true
  defp authorized?(job, caller_project_id), do: job.project_id == caller_project_id

  defp check_authorized(job, caller_project_id) do
    if authorized?(job, caller_project_id), do: :ok, else: {:error, :unauthorized}
  end

  defp update_job_fields(job, fields) do
    job |> ScheduledJob.changeset(fields) |> Repo.update()
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp fs_agent_already_scheduled?(attrs) do
    # Only applies to fs: agents (no prompt_id, agent_file_id in config)
    prompt_id = attrs["prompt_id"]

    if prompt_id != nil and prompt_id != "" do
      false
    else
      agent_file_id = extract_agent_file_id(attrs["config"])
      scheduled_for_agent_file?(agent_file_id)
    end
  end

  defp extract_agent_file_id(config_str) do
    case config_str do
      str when is_binary(str) ->
        case Jason.decode(str) do
          {:ok, %{"agent_file_id" => id}} when is_binary(id) -> id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp scheduled_for_agent_file?(nil), do: false

  defp scheduled_for_agent_file?(agent_file_id) do
    from(j in ScheduledJob,
      where: j.job_type == "spawn_agent" and is_nil(j.prompt_id),
      where: fragment("config::jsonb->>'agent_file_id' = ?", ^agent_file_id)
    )
    |> Repo.exists?()
  end

  defp maybe_encode_config(attrs) do
    case attrs["config"] do
      val when is_map(val) -> Map.put(attrs, "config", Jason.encode!(val))
      _ -> attrs
    end
  end

end
