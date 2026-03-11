defmodule EyeInTheSkyWeb.Workers.SpawnAgentWorker do
  use Oban.Worker, queue: :jobs, max_attempts: 3

  alias EyeInTheSkyWeb.ScheduledJobs
  alias EyeInTheSkyWeb.Claude.AgentManager

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    job = ScheduledJobs.get_job!(job_id)
    {:ok, run} = ScheduledJobs.record_run_start(job)

    case execute(job) do
      {:ok, output, opts} ->
        ScheduledJobs.record_run_complete(run, "completed",
          result: output,
          session_id: opts[:session_id]
        )

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
    session_uuid = Ecto.UUID.generate()
    base_url = EyeInTheSkyWebWeb.Endpoint.url()
    dm_link = "#{base_url}/dm/#{session_uuid}"

    base_instructions = config["instructions"] || "Scheduled agent task"

    instructions =
      base_instructions <>
        "\n\nYour DM page link (include this in any notifications): #{dm_link}"

    opts = [
      instructions: instructions,
      model: config["model"],
      project_path: config["project_path"],
      description: config["description"] || "Scheduled agent",
      project_id: job.project_id,
      session_uuid: session_uuid
    ]

    case AgentManager.create_agent(opts) do
      {:ok, %{session: session}} ->
        {:ok, "Agent spawned", session_id: session.id}

      {:error, reason} ->
        {:error, "Failed to spawn agent: #{inspect(reason)}"}
    end
  end

  defp broadcast do
    Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "scheduled_jobs", :jobs_updated)
  end
end
