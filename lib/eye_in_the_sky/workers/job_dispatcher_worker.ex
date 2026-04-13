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
    for job <- ScheduledJobs.due_jobs() do
      case ScheduledJobs.claim_job(job) do
        :ok ->
          case ScheduledJobs.enqueue_job(job) do
            {:ok, _} ->
              case ScheduledJobs.mark_job_executed(job) do
                {:ok, _} ->
                  :ok

                {:error, reason} ->
                  Logger.error("JobDispatcherWorker: mark_job_executed failed for job #{job.id}: #{inspect(reason)}")
              end

            {:error, reason} ->
              Logger.error("JobDispatcherWorker: failed to enqueue job #{job.id}: #{inspect(reason)}")
              ScheduledJobs.release_claim(job, job.next_run_at)
          end

        {:error, :already_claimed} ->
          :ok
      end
    end

    :ok
  end
end
