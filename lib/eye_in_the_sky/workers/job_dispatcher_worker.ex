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
      case ScheduledJobs.enqueue_job(job) do
        {:ok, _} ->
          ScheduledJobs.mark_job_executed(job)

        {:error, reason} ->
          Logger.error("JobDispatcherWorker: failed to enqueue job #{job.id}: #{inspect(reason)}")
      end
    end

    :ok
  end
end
