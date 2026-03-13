defmodule EyeInTheSkyWeb.Workers.ShellCommandWorker do
  use Oban.Worker, queue: :jobs, max_attempts: 3

  alias EyeInTheSkyWeb.ScheduledJobs

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    job = ScheduledJobs.get_job!(job_id)
    {:ok, run} = ScheduledJobs.record_run_start(job)

    case execute(job) do
      {:ok, output} ->
        ScheduledJobs.record_run_complete(run, "completed", result: output)
        broadcast()
        :ok

      {:error, reason} ->
        ScheduledJobs.record_run_complete(run, "failed", result: reason)
        broadcast()
        {:error, reason}
    end
  end

  defp execute(job) do
    config = ScheduledJobs.decode_config(job)
    command = config["command"] || "echo 'no command'"
    working_dir = blank_to_nil(config["working_dir"]) || File.cwd!()
    timeout = config["timeout_ms"] || 30_000

    task =
      Task.async(fn ->
        System.cmd("sh", ["-c", command], cd: working_dir, stderr_to_stdout: true)
      end)

    try do
      case Task.await(task, timeout) do
        {output, 0} -> {:ok, String.trim(output)}
        {output, exit_code} -> {:error, "Exit code #{exit_code}: #{String.trim(output)}"}
      end
    rescue
      e -> {:error, "Command failed: #{inspect(e)}"}
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        {:error, "Command timed out after #{timeout}ms"}
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp broadcast do
    Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "scheduled_jobs", :jobs_updated)
  end
end
