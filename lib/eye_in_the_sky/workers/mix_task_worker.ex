defmodule EyeInTheSky.Workers.MixTaskWorker do
  @moduledoc false
  use Oban.Worker, queue: :jobs, max_attempts: 3

  alias EyeInTheSky.ScheduledJobs

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
    task = config["task"] || "help"
    args = config["args"] || []
    project_path = blank_to_nil(config["project_path"]) || File.cwd!()

    {output, exit_code} =
      System.cmd("mix", [task | args], cd: project_path, stderr_to_stdout: true)

    if exit_code == 0 do
      {:ok, String.trim(output)}
    else
      {:error, "Exit code #{exit_code}: #{String.trim(output)}"}
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp broadcast do
    EyeInTheSky.Events.jobs_updated()
  end
end
