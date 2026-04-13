defmodule EyeInTheSky.Workers.MixTaskWorker do
  @moduledoc false
  use Oban.Worker, queue: :jobs, max_attempts: 3

  require Logger

  alias EyeInTheSky.ScheduledJobs

  @allowed_tasks ~w(test format deps.get assets.deploy ecto.migrate ecto.rollback help)

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

    raw_args = config["args"] || []

    args =
      if is_list(raw_args) do
        raw_args
      else
        Logger.warning(
          "[MixTaskWorker] config[\"args\"] is not a list (got #{inspect(raw_args)}), coercing to []"
        )

        []
      end

    if is_binary(task) && task in @allowed_tasks do
      project_path = blank_to_nil(config["project_path"]) || File.cwd!()

      {output, exit_code} =
        System.cmd("mix", [task | args], cd: project_path, stderr_to_stdout: true)

      if exit_code == 0 do
        {:ok, String.trim(output)}
      else
        {:error, "Exit code #{exit_code}: #{String.trim(output)}"}
      end
    else
      {:error, "Disallowed mix task: #{inspect(task)}"}
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp broadcast do
    EyeInTheSky.Events.jobs_updated()
  end
end
