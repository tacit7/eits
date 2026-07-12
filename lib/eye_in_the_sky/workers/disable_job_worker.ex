defmodule EyeInTheSky.Workers.DisableJobWorker do
  @moduledoc """
  Disables one or more scheduled jobs by ID.

  Config keys:
  - `job_ids` (list of integers, required) — IDs of jobs to disable
  - `job_id`  (integer, optional)          — single-job shorthand; merged with job_ids

  Runs via Oban on the :jobs queue. Intended for scheduled "turn off X at time Y" patterns.
  """
  use Oban.Worker, queue: :jobs, max_attempts: 3

  require Logger

  alias EyeInTheSky.ScheduledJobs

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    job = ScheduledJobs.get_job!(job_id)
    {:ok, run} = ScheduledJobs.record_run_start(job)

    case execute(job) do
      {:ok, output} ->
        ScheduledJobs.record_run_complete(run, "completed", result: output)
        EyeInTheSky.Events.jobs_updated()
        :ok

      {:error, reason} ->
        ScheduledJobs.record_run_complete(run, "failed", result: reason)
        EyeInTheSky.Events.jobs_updated()
        {:error, reason}
    end
  end

  defp execute(job) do
    config = ScheduledJobs.decode_config(job)

    target_ids =
      (List.wrap(config["job_ids"]) ++ List.wrap(config["job_id"]))
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    if target_ids == [] do
      {:error, "No job_ids specified in config"}
    else
      {succeeded, failed} = ScheduledJobs.bulk_update_enabled(target_ids, false, job.project_id)

      Logger.info("[DisableJobWorker] disabled #{succeeded} job(s), #{failed} failed/unauthorized")

      if failed > 0 do
        {:error, "Disabled #{succeeded}, failed/unauthorized #{failed}"}
      else
        {:ok, "Disabled job(s): #{Enum.join(target_ids, ", ")}"}
      end
    end
  end
end
