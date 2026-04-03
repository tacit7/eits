defmodule EyeInTheSky.Workers.ShellCommandWorker do
  use Oban.Worker, queue: :jobs, max_attempts: 3

  alias EyeInTheSky.ScheduledJobs

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    job = ScheduledJobs.get_job!(job_id)
    {:ok, run} = ScheduledJobs.record_run_start(job)

    try do
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
    rescue
      e ->
        ScheduledJobs.record_run_complete(run, "failed", result: Exception.message(e))
        broadcast()
        reraise e, __STACKTRACE__
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
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        {:error, "Command timed out after #{timeout}ms"}

      :exit, reason ->
        {:error, "Task exited: #{inspect(reason)}"}
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp broadcast do
    EyeInTheSky.Events.jobs_updated()
  end
end
