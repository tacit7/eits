defmodule EyeInTheSky.Agents.AgentManager.SessionBridge do
  @moduledoc """
  Session and worker lifecycle concerns for AgentManager.

  Handles finding or starting an AgentWorker for a given session,
  loading session/agent records from the database, and provider validation.
  """

  require Logger

  alias EyeInTheSky.{Agents, Projects, Sessions}
  alias EyeInTheSky.Claude.AgentWorker

  @registry EyeInTheSky.Claude.AgentRegistry
  @supported_providers ["claude", "codex"]

  @doc """
  Finds an existing AgentWorker in the registry or starts a new one.
  Returns `{:ok, pid, provider}` or `{:error, reason}`.
  """
  def ensure_worker_running(session_id, extra_opts) do
    case Registry.lookup(@registry, {:session, session_id}) do
      [{pid, provider}] ->
        if Process.alive?(pid) do
          Logger.debug(
            "ensure_worker_running: found existing worker for session_id=#{session_id}, pid=#{inspect(pid)}, provider=#{provider}"
          )

          {:ok, pid, provider}
        else
          start_worker(session_id, extra_opts)
        end

      [] ->
        Logger.info(
          "🔍 ensure_worker_running: no worker found for session_id=#{session_id}, starting new worker"
        )

        start_worker(session_id, extra_opts)
    end
  end

  defp start_worker(session_id, extra_opts) do
    Logger.info("🚀 start_worker: loading session.id=#{session_id}")

    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, agent} <- Agents.get_agent(session.agent_id),
         provider when not is_nil(provider) <- normalize_provider(session.provider),
         {:ok, session} <- ensure_session_uuid(session, provider),
         {:ok, project_path} <- resolve_project_path(session, agent) do
      Logger.info(
        "✅ start_worker: loaded session.uuid=#{session.uuid}, agent.id=#{agent.id}, project_path=#{project_path}"
      )

      spawn_worker(session, agent, provider, project_path, extra_opts)
    else
      nil ->
        {:error, {:unsupported_provider, nil}}

      {:error, reason} ->
        Logger.error("❌ start_worker: failed for session.id=#{session_id} - #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp normalize_provider(provider) when provider in @supported_providers, do: provider
  defp normalize_provider(_provider), do: nil

  defp resolve_project_path(session, agent) do
    cond do
      session.git_worktree_path ->
        {:ok, session.git_worktree_path}

      agent.git_worktree_path ->
        {:ok, agent.git_worktree_path}

      agent.project && agent.project.path ->
        {:ok, agent.project.path}

      session.project_id ->
        lookup_project_path(session.project_id, "session.project_id", session.id)

      agent.project_id ->
        lookup_project_path(agent.project_id, "agent.project_id", session.id)

      agent.project_name ->
        lookup_project_path_by_basename(agent.project_name, session.id)

      true ->
        Logger.error(
          "resolve_project_path: no path for session.id=#{session.id}; " <>
            "all resolution strategies exhausted " <>
            "(session.project_id=nil, agent.project_id=nil, agent.project_name=nil, " <>
            "session.git_worktree_path=nil, agent.git_worktree_path=nil)"
        )

        {:error, :missing_project_path}
    end
  end

  defp lookup_project_path(project_id, source, session_id) do
    case Projects.get_project(project_id) do
      {:ok, %{path: path}} when not is_nil(path) ->
        Logger.info(
          "resolve_project_path: resolved via #{source}=#{project_id} for session.id=#{session_id}"
        )

        {:ok, path}

      {:ok, project} ->
        Logger.error(
          "resolve_project_path: #{source}=#{project_id} found project.id=#{project.id} " <>
            "but path is nil for session.id=#{session_id}"
        )

        {:error, :missing_project_path}

      {:error, :not_found} ->
        Logger.error(
          "resolve_project_path: #{source}=#{project_id} not found in projects table " <>
            "for session.id=#{session_id}"
        )

        {:error, :missing_project_path}
    end
  end

  defp lookup_project_path_by_basename(project_name, session_id) do
    case Projects.get_project_by_path_basename(project_name) do
      {:ok, %{path: path} = project} when not is_nil(path) ->
        Logger.info(
          "resolve_project_path: resolved via project_name=#{project_name} -> " <>
            "project.id=#{project.id}, path=#{path} for session.id=#{session_id}"
        )

        {:ok, path}

      {:ok, project} ->
        Logger.error(
          "resolve_project_path: project_name=#{project_name} matched project.id=#{project.id} " <>
            "but path is nil for session.id=#{session_id}"
        )

        {:error, :missing_project_path}

      {:error, :not_found} ->
        Logger.error(
          "resolve_project_path: project_name=#{project_name} did not match any project path " <>
            "for session.id=#{session_id}"
        )

        {:error, :missing_project_path}
    end
  end

  # Codex sessions intentionally start with uuid=nil — the real UUID (provider thread_id)
  # arrives via the thread.started event and is synced by on_provider_conversation_id_changed.
  # Generating a temp UUID here would become stale and break dm resolve_session lookups.
  defp ensure_session_uuid(session, "codex"), do: {:ok, session}

  defp ensure_session_uuid(session, _provider) do
    if is_nil(session.uuid) or session.uuid == "" do
      uuid = Ecto.UUID.generate()
      Logger.info("ensure_session_uuid: generating UUID=#{uuid} for session.id=#{session.id}")

      case Sessions.update_session(session, %{uuid: uuid}) do
        {:ok, updated} -> {:ok, updated}
        {:error, reason} -> {:error, {:session_update_failed, reason}}
      end
    else
      {:ok, session}
    end
  end

  defp spawn_worker(session, agent, provider, project_path, extra_opts) do
    opts = [
      session_id: session.id,
      # eits_session_uuid: stable EITS session UUID, never changes after assignment.
      # Used for EITS tracking, env vars, and hooks. Distinct from provider_conversation_id.
      eits_session_uuid: session.uuid,
      # provider_conversation_id: the provider's resume key.
      #   Claude: pre-generated UUID matching Claude's --session-id flag
      #   Codex:  same value initially, but gets overwritten by the Codex thread_id
      #           when the thread.started event fires (via maybe_sync_provider_conversation_id)
      provider_conversation_id: session.uuid,
      agent_id: agent.id,
      project_id: session.project_id,
      project_path: project_path,
      provider: provider,
      worktree: extra_opts[:worktree]
    ]

    case DynamicSupervisor.start_child(
           EyeInTheSky.Claude.AgentSupervisor,
           {AgentWorker, opts}
         ) do
      {:ok, pid} ->
        Logger.info("✅ spawn_worker: started for session.id=#{session.id}, pid=#{inspect(pid)}")

        {:ok, pid, provider}

      {:error, {:already_started, pid}} ->
        Logger.info(
          "spawn_worker: already started for session.id=#{session.id}, pid=#{inspect(pid)}"
        )

        {:ok, pid, provider}

      {:error, reason} = error ->
        Logger.error("❌ spawn_worker: failed for session.id=#{session.id} - #{inspect(reason)}")

        error
    end
  end
end
