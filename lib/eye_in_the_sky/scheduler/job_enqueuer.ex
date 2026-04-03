defmodule EyeInTheSky.Scheduler.JobEnqueuer do
  @moduledoc """
  Thin GenServer that polls scheduled_jobs for due jobs and enqueues Oban workers.
  Replaces the old JobScheduler that handled both scheduling and execution.
  """

  use GenServer

  require Logger

  alias EyeInTheSky.ScheduledJobs

  @check_interval 30_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc "Immediately enqueue a job for execution (for 'Run Now' button)."
  def run_now(job_id) do
    case ScheduledJobs.get_job(job_id) do
      {:ok, job} ->
        case ScheduledJobs.enqueue_job(job) do
          {:ok, _} = result ->
            ScheduledJobs.mark_job_executed(job)
            result

          error ->
            error
        end

      {:error, _} = err ->
        err
    end
  end

  @impl GenServer
  def init(nil) do
    Process.send_after(self(), :check_jobs, 5_000)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:check_jobs, state) do
    for job <- ScheduledJobs.due_jobs() do
      case ScheduledJobs.enqueue_job(job) do
        {:ok, _} -> ScheduledJobs.mark_job_executed(job)
        {:error, reason} -> Logger.error("Failed to enqueue job #{job.id}: #{inspect(reason)}")
      end
    end

    Process.send_after(self(), :check_jobs, @check_interval)
    {:noreply, state}
  rescue
    DBConnection.ConnectionError ->
      Logger.error("JobEnqueuer check failed: DB connection unavailable")
      Process.send_after(self(), :check_jobs, @check_interval)
      {:noreply, state}
  end
end
