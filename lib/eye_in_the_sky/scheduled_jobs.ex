defmodule EyeInTheSky.ScheduledJobs do
  @moduledoc false
  import Ecto.Query, warn: false

  require Logger

  alias EyeInTheSky.Repo
  alias EyeInTheSky.ScheduledJobs.ScheduledJob
  alias EyeInTheSky.ScheduledJobs.CronParser
  alias EyeInTheSky.ScheduledJobs.JobRunTracker
  alias EyeInTheSky.ScheduledJobs.JobScheduler

  # ---------------------------------------------------------------------------
  # Run tracking — delegated to JobRunTracker
  # ---------------------------------------------------------------------------

  defdelegate list_running_job_ids(), to: JobRunTracker
  defdelegate last_run_status_map(), to: JobRunTracker
  defdelegate list_runs_for_job(job_id, opts \\ []), to: JobRunTracker
  defdelegate last_run_per_job(job_ids), to: JobRunTracker
  defdelegate record_run_start(job), to: JobRunTracker
  defdelegate record_run_complete(run, status, opts \\ []), to: JobRunTracker

  # ---------------------------------------------------------------------------
  # Scheduling math — delegated to JobScheduler
  # ---------------------------------------------------------------------------

  defdelegate compute_next_run_at(
                schedule_type,
                schedule_value,
                from \\ nil,
                timezone \\ "Etc/UTC"
              ),
              to: CronParser

  defdelegate due_jobs(), to: JobScheduler
  defdelegate claim_job(job), to: JobScheduler
  defdelegate release_claim(job, sentinel, original_next_run_at), to: JobScheduler
  defdelegate mark_job_executed(job), to: JobScheduler

  # ---------------------------------------------------------------------------
  # CRUD
  # ---------------------------------------------------------------------------

  def list_jobs(opts \\ []) do
    opts
    |> list_jobs_filters()
    |> base_jobs_query()
    |> order_by([j], asc: j.origin, asc: j.name)
    |> Repo.all()
  end

  def list_spawn_agent_jobs_by_prompt_ids(prompt_ids) when is_list(prompt_ids) do
    base_jobs_query(prompt_ids: prompt_ids)
    |> Repo.all()
  end

  def list_filesystem_agent_jobs do
    base_jobs_query(job_type: "spawn_agent", prompt_id_nil: true, config_contains: "%agent_file_id%")
    |> Repo.all()
  end

  def list_orphaned_agent_jobs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    from(j in ScheduledJob,
      join: p in assoc(j, :prompt),
      where: j.job_type == "spawn_agent",
      where: not is_nil(j.prompt_id),
      where: p.active == false,
      limit: ^limit
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
          JobScheduler.compute_next_run_at(
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
      next =
        JobScheduler.compute_next_run_at(
          updated.schedule_type,
          updated.schedule_value,
          nil,
          updated.timezone || "Etc/UTC"
        )

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
        case JobScheduler.mark_job_executed(job) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "run_now: mark_job_executed failed for job #{job.id}: #{inspect(reason)}"
            )
        end

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
      new_enabled = not job.enabled
      update_job_fields(job, %{enabled: new_enabled, updated_at: DateTime.utc_now()})
    else
      {:error, :unauthorized}
    end
  end

  def change_job(%ScheduledJob{} = job, attrs \\ %{}) do
    ScheduledJob.changeset(job, attrs)
  end

  # ---------------------------------------------------------------------------
  # Config helpers
  # ---------------------------------------------------------------------------

  def decode_config(%ScheduledJob{config: config}) when is_binary(config) do
    case Jason.decode(config) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  def decode_config(_), do: %{}

  def encode_config(map) when is_map(map), do: Jason.encode!(map)
  def encode_config(str) when is_binary(str), do: str

  # ---------------------------------------------------------------------------
  # Oban enqueueing
  # ---------------------------------------------------------------------------

  @doc "Enqueue the appropriate Oban worker for a scheduled job."
  def enqueue_job(%ScheduledJob{} = job) do
    case job.job_type do
      "spawn_agent" -> do_enqueue(EyeInTheSky.Workers.SpawnAgentWorker, job)
      "mix_task" -> do_enqueue(EyeInTheSky.Workers.MixTaskWorker, job)
      "daily_digest" -> do_enqueue(EyeInTheSky.Workers.DailyDigestWorker, job)
      "workable_task" -> do_enqueue(EyeInTheSky.Workers.WorkableTaskWorker, job)
      other -> {:error, {:unknown_job_type, other}}
    end
  end

  defp do_enqueue(worker, job) do
    %{"job_id" => job.id}
    |> worker.new(
      unique: [period: 30, fields: [:args, :worker], states: [:available, :scheduled, :executing]]
    )
    |> Oban.insert()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp base_jobs_query(filters) do
    Enum.reduce(filters, ScheduledJob, fn
      {:project_id, id}, q -> where(q, [j], j.project_id == ^id)
      {:global_only, true}, q -> where(q, [j], is_nil(j.project_id))
      {:prompt_ids, ids}, q -> where(q, [j], j.prompt_id in ^ids)
      {:job_type, type}, q -> where(q, [j], j.job_type == ^type)
      {:prompt_id_nil, true}, q -> where(q, [j], is_nil(j.prompt_id))
      {:config_contains, pattern}, q -> where(q, [j], like(j.config, ^pattern))
      _, q -> q
    end)
  end

  defp list_jobs_filters(opts) do
    case Keyword.get(opts, :project_id) do
      nil -> if Keyword.get(opts, :global_only, false), do: [global_only: true], else: []
      id -> [project_id: id]
    end
  end

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
    case attrs["prompt_id"] do
      p when p in [nil, ""] ->
        attrs["config"] |> extract_agent_file_id() |> scheduled_for_agent_file?()

      _ ->
        false
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
