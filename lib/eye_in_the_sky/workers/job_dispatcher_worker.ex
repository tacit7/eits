defmodule EyeInTheSky.Workers.JobDispatcherWorker do
  @moduledoc """
  Oban worker that replaces the JobEnqueuer GenServer poll loop.
  Registered in Oban.Plugins.Cron to run every minute, it queries
  due scheduled_jobs and enqueues the appropriate execution worker.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias EyeInTheSky.ScheduledJobs

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    jobs_mod = Application.get_env(:eye_in_the_sky, :jobs_module, ScheduledJobs)

    for job <- jobs_mod.due_jobs() do
      case jobs_mod.claim_job(job) do
        {:ok, sentinel} -> dispatch_job(jobs_mod, job, sentinel)
        {:error, :already_claimed} -> :ok
      end
    end

    :ok
  end

  # Enqueue then mark executed. The two error paths have different semantics:
  # - enqueue failure: release the claim so the next tick can retry
  # - mark_executed failure: job already enqueued, do NOT release (would cause re-enqueue)
  defp dispatch_job(jobs_mod, job, sentinel) do
    with {:ok, _} <- enqueue_job_or_error(jobs_mod, job),
         {:ok, _} <- mark_job_executed_or_error(jobs_mod, job) do
      :ok
    else
      {:error, {:enqueue_failed, reason}} ->
        Logger.error("JobDispatcherWorker: failed to enqueue job #{job.id}: #{inspect(reason)}")
        jobs_mod.release_claim(job, sentinel, job.next_run_at)
        :error

      {:error, {:mark_failed, reason}} ->
        Logger.error(
          "JobDispatcherWorker: mark_job_executed failed for job #{job.id}: #{inspect(reason)}"
        )

        :error
    end
  end

  defp enqueue_job_or_error(jobs_mod, job) do
    case jobs_mod.enqueue_job(job) do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, {:enqueue_failed, reason}}
    end
  end

  defp mark_job_executed_or_error(jobs_mod, job) do
    case jobs_mod.mark_job_executed(job) do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, {:mark_failed, reason}}
    end
  end
end
