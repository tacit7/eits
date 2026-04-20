defmodule EyeInTheSky.Workers.SpawnAgentWorker do
  @moduledoc false
  use Oban.Worker, queue: :jobs, max_attempts: 3

  require Logger

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.ScheduledJobs
  alias EyeInTheSky.Utils.ToolHelpers

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
    base_url = server_base_url()
    dm_link = "#{base_url}/dm/#{session_uuid}"

    base_instructions = config["instructions"] || "Scheduled agent task"

    instructions =
      base_instructions <>
        "\n\nYour DM page link (include this in any notifications): #{dm_link}"

    opts = build_agent_opts(config, session_uuid, instructions, job)

    log_opts = Keyword.drop(opts, [:instructions])

    Logger.info(
      "[telemetry] spawn_agent_worker job_id=#{job.id} name=#{job.name} opts=#{inspect(log_opts)}"
    )

    case AgentManager.create_agent(opts) do
      {:ok, %{session: session}} ->
        {:ok, "Agent spawned", session_id: session.id}

      {:error, reason} ->
        {:error, "Failed to spawn agent: #{inspect(reason)}"}
    end
  end

  defp build_agent_opts(config, session_uuid, instructions, job) do
    [
      instructions: instructions,
      model: config["model"],
      project_path: config["project_path"],
      description: config["description"] || "Scheduled agent",
      project_id: job.project_id,
      session_uuid: session_uuid
    ]
    |> maybe_put(:max_budget_usd, parse_float(config["max_budget_usd"]))
    |> maybe_put(:max_turns, ToolHelpers.parse_int(config["max_turns"]))
    |> maybe_put(:fallback_model, config["fallback_model"])
    |> maybe_put(:allowed_tools, config["allowed_tools"])
    |> maybe_put(:output_format, config["output_format"])
    |> maybe_put(:skip_permissions, config["skip_permissions"])
    |> maybe_put(:permission_mode, config["permission_mode"])
    |> maybe_put(:add_dir, config["add_dir"])
    |> maybe_put(:mcp_config, config["mcp_config"])
    |> maybe_put(:plugin_dir, config["plugin_dir"])
    |> maybe_put(:settings_file, config["settings_file"])
    |> maybe_put(:chrome, config["chrome"])
    |> maybe_put(:sandbox, config["sandbox"])
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, val), do: Keyword.put(opts, key, val)

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, ""} -> f
      _ -> nil
    end
  end

  defp parse_float(val) when is_number(val), do: val

  defp broadcast do
    EyeInTheSky.Events.jobs_updated()
  end

  defp server_base_url do
    Application.get_env(:eye_in_the_sky, :server_base_url, "http://localhost:5001")
  end
end
