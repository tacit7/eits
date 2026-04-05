defmodule EyeInTheSky.Agents.AgentManager do
  @moduledoc """
  Manages AgentWorker lifecycle - spawn on demand, lookup existing workers.

  Ensures only one AgentWorker per session and handles message routing.
  """

  require Logger

  alias EyeInTheSky.Agents.{InstructionBuilder, RuntimeContext}
  alias EyeInTheSky.Claude.AgentWorker
  alias EyeInTheSky.Git.Worktrees
  alias EyeInTheSky.{AgentDefinitions, Agents, Sessions}
  alias EyeInTheSky.Utils.ToolHelpers
  alias EyeInTheSkyWeb.Live.Shared.SessionHelpers

  @registry EyeInTheSky.Claude.AgentRegistry
  @supported_providers ["claude", "codex"]

  @doc """
  Creates an agent + session and starts the AgentWorker with the initial message.

  ## Options
    * `:agent_type` - Agent type (e.g., "claude", "codex"). Default: "claude"
    * `:model` - Model to use. If not provided, uses Claude's default.
    * `:effort_level` - Effort level for the model
    * `:project_id` - Project ID to associate with
    * `:project_path` - Working directory for Claude
    * `:description` - Human-readable agent description
    * `:instructions` - Initial prompt/instructions for the agent

  Returns `{:ok, %{agent: agent, session: session}}` or `{:error, reason}`.
  """
  def create_agent(opts) do
    with {:ok, %{agent: agent, session: session}} <- create_records(opts) do
      instructions = InstructionBuilder.build(opts)

      Logger.info("📤 create_agent: sending initial message to session.id=#{session.id}")

      # Forward all opts to send_message so RuntimeContext.build can pick up
      # known keys (model, effort_level, etc.) and pass the rest as extra_cli_opts
      # to CLI.build_args (permission_mode, add_dir, chrome, sandbox, etc.)
      send_opts =
        opts
        |> Keyword.drop([:agent_type, :project_id, :project_path, :description, :instructions])

      case send_message(session.id, instructions, send_opts) do
        {:ok, admission} ->
          # Only mark "running" when the SDK actually started. :retry_queued means
          # the spawn failed and was queued for retry — agent stays "pending".
          status = admission_to_status(admission)

          Logger.info(
            "✅ create_agent: admission=#{admission} for session.id=#{session.id}, setting status=#{status}"
          )

          update_agent_after_send(agent, session, status)

        {:error, reason} ->
          Logger.error(
            "❌ create_agent: initial message failed for session.id=#{session.id} - #{inspect(reason)}"
          )

          mark_agent_failed(agent)
          {:error, {:send_failed, reason}}
      end
    end
  end

  defp admission_to_status(:started), do: "running"
  defp admission_to_status(_), do: "pending"

  defp update_agent_after_send(agent, session, status) do
    case Agents.update_agent(agent, %{status: status}) do
      {:ok, updated_agent} ->
        {:ok, %{agent: updated_agent, session: session}}

      {:error, reason} ->
        Logger.warning(
          "create_agent: agent status update to '#{status}' failed for agent.id=#{agent.id} - #{inspect(reason)}"
        )

        # Non-fatal: dispatch succeeded, return original agent
        {:ok, %{agent: agent, session: session}}
    end
  end

  defp mark_agent_failed(agent) do
    case Agents.update_agent(agent, %{status: "failed"}) do
      {:ok, _} ->
        :ok

      {:error, update_err} ->
        Logger.warning(
          "create_agent: agent status update to 'failed' failed for agent.id=#{agent.id} - #{inspect(update_err)}"
        )
    end
  end

  defp create_records(opts) do
    agent_uuid = Ecto.UUID.generate()
    provider = resolve_provider(opts)
    session_uuid = resolve_session_uuid(provider, opts)
    description = resolve_description(opts)
    project_id = resolve_project_id(opts)

    Logger.info(
      "📝 create_agent: agent_uuid=#{agent_uuid}, session_uuid=#{inspect(session_uuid)}, model=#{opts[:model]}, project_id=#{project_id}"
    )

    definition_info = resolve_agent_definition(opts[:agent], project_id, opts[:project_path])

    with {:ok, worktree_path} <- resolve_worktree_path(opts) do
      insert_agent_and_session(%{
        agent_uuid: agent_uuid,
        provider: provider,
        session_uuid: session_uuid,
        description: description,
        project_id: project_id,
        worktree_path: worktree_path,
        definition_info: definition_info,
        opts: opts
      })
    end
  end

  defp resolve_provider(opts) do
    if opts[:agent_type] == "codex", do: "codex", else: "claude"
  end

  defp resolve_session_uuid(provider, opts) do
    # For codex sessions, leave uuid null — Codex thread_id arrives via thread.started event
    # and gets synced to the session via maybe_sync_provider_conversation_id.
    # For claude sessions, pre-generate so the worker can reference it immediately.
    if provider == "codex", do: nil, else: opts[:session_uuid] || Ecto.UUID.generate()
  end

  defp resolve_description(opts) do
    opts[:description] || "Agent session"
  end

  defp resolve_project_id(opts) do
    opts[:project_id] ||
      with parent_id when not is_nil(parent_id) <- opts[:parent_session_id],
           {:ok, parent} <- Sessions.get_session(parent_id) do
        parent.project_id
      else
        _ -> nil
      end
  end

  defp resolve_worktree_path(opts) do
    # When a worktree name is given, create the git worktree before DB records.
    # If creation fails, return an error — do NOT silently fall back to the main project path.
    case opts[:worktree] do
      nil ->
        {:ok, opts[:project_path]}

      wt ->
        case Worktrees.prepare_session_worktree(opts[:project_path], wt) do
          {:ok, _} = ok ->
            ok

          {:error, reason} = err ->
            Logger.error("create_agent: git worktree setup failed for #{wt}: #{inspect(reason)}")

            err
        end
    end
  end

  defp insert_agent_and_session(%{
         agent_uuid: agent_uuid,
         provider: provider,
         session_uuid: session_uuid,
         description: description,
         project_id: project_id,
         worktree_path: worktree_path,
         definition_info: definition_info,
         opts: opts
       }) do
    with {:ok, agent} <-
           Agents.create_agent(
             %{
               uuid: agent_uuid,
               agent_type: opts[:agent_type] || "claude",
               project_id: project_id,
               project_name: opts[:project_name],
               status: "pending",
               description: description,
               git_worktree_path: worktree_path,
               parent_agent_id: opts[:parent_agent_id],
               parent_session_id: opts[:parent_session_id]
             }
             |> maybe_put_definition(definition_info)
           ),
         {:ok, session} <-
           Sessions.create_session(%{
             uuid: session_uuid,
             agent_id: agent.id,
             name: description,
             description: "agent-id #{agent_uuid}",
             model: opts[:model],
             provider: provider,
             project_id: project_id,
             git_worktree_path: worktree_path,
             started_at: DateTime.utc_now(),
             parent_agent_id: opts[:parent_agent_id],
             parent_session_id: opts[:parent_session_id]
           }) do
      Logger.info(
        "✅ create_agent: DB records created - agent.id=#{agent.id}, session.id=#{session.id}, session_uuid=#{session.uuid}"
      )

      {:ok, %{agent: agent, session: session}}
    else
      {:error, reason} ->
        Logger.error("❌ create_agent: DB record creation failed - #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Continues an existing session with a new prompt.
  Looks up or starts an AgentWorker and sends the message.
  Automatically resumes the Claude session if prior messages exist.
  """
  def continue_session(session_id, prompt, opts \\ []) do
    send_message(session_id, prompt, opts)
  end

  @doc """
  Cancels the currently running SDK process for a session.
  """
  def cancel_session(session_id) do
    AgentWorker.cancel(session_id)
  end

  def send_message(session_id, message, opts \\ [])

  def send_message(session_id, message, opts) when is_binary(message) do
    Logger.debug(
      "send_message: session_id=#{session_id}, message_length=#{String.length(message)}"
    )

    case lookup_or_start(session_id, opts) do
      {:ok, pid, provider} ->
        Logger.debug(
          "send_message: worker found/started for session_id=#{session_id}, pid=#{inspect(pid)}"
        )

        context = RuntimeContext.build(session_id, provider, opts)

        try do
          case GenServer.call(pid, {:submit_message, message, context}) do
            {:ok, admission} ->
              Logger.debug("send_message: #{admission} for session_id=#{session_id}")

              {:ok, admission}

            {:error, reason} = error ->
              Logger.warning(
                "send_message: rejected for session_id=#{session_id} - #{inspect(reason)}"
              )

              error
          end
        catch
          :exit, {:noproc, _} ->
            Logger.warning("send_message: worker died before call for session_id=#{session_id}")
            {:error, :worker_not_found}

          :exit, reason ->
            Logger.error("send_message: worker exit for session_id=#{session_id} - #{inspect(reason)}")
            {:error, {:worker_exit, reason}}
        end

      {:error, reason} ->
        Logger.error(
          "❌ send_message: failed to lookup/start worker for session_id=#{session_id} - #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  def send_message(session_id, _message, _opts) do
    Logger.warning("send_message: invalid message payload for session_id=#{session_id}")
    {:error, :invalid_message}
  end

  defp lookup_or_start(session_id, extra_opts) do
    # Invariant: exactly one AgentWorker per session, keyed by {:session, session_id}
    case Registry.lookup(@registry, {:session, session_id}) do
      [{pid, provider}] ->
        if Process.alive?(pid) do
          Logger.debug(
            "lookup_or_start: found existing worker for session_id=#{session_id}, pid=#{inspect(pid)}, provider=#{provider}"
          )

          {:ok, pid, provider}
        else
          start_agent_worker(session_id, extra_opts)
        end

      [] ->
        Logger.info(
          "🔍 lookup_or_start: no worker found for session_id=#{session_id}, starting new worker"
        )

        start_agent_worker(session_id, extra_opts)
    end
  end

  defp start_agent_worker(session_id, extra_opts) do
    Logger.info("🚀 start_agent_worker: loading session.id=#{session_id}")

    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, agent} <- Agents.get_agent(session.agent_id),
         provider when not is_nil(provider) <- normalize_provider(session.provider),
         {:ok, session} <- ensure_session_uuid(session, provider) do
      project_path = resolve_project_path_with_fallback(session, agent)

      Logger.info(
        "✅ start_agent_worker: loaded session.uuid=#{session.uuid}, agent.id=#{agent.id}, project_path=#{project_path}"
      )

      spawn_worker(session, agent, provider, project_path, extra_opts)
    else
      nil ->
        {:error, {:unsupported_provider, nil}}

      {:error, reason} ->
        Logger.error(
          "❌ start_agent_worker: failed for session.id=#{session_id} - #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp resolve_project_path_with_fallback(session, agent) do
    case SessionHelpers.resolve_project_path(session, agent) do
      {:ok, path} ->
        path

      {:error, :no_project_path} ->
        fallback = File.cwd!()

        Logger.error(
          "resolve_project_path: no path for session.id=#{session.id}; " <>
            "session.git_worktree_path=#{inspect(session.git_worktree_path)}, " <>
            "agent.git_worktree_path=#{inspect(agent.git_worktree_path)}, " <>
            "project.path=#{inspect(if agent.project, do: agent.project.path)} — falling back to cwd=#{fallback}"
        )

        fallback
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

  defp normalize_provider(provider) when provider in @supported_providers, do: provider
  defp normalize_provider(_provider), do: nil

  # ── Agent definition resolution ────────────────────────────────────────

  # Resolves an agent slug to a definition record. Returns a map with
  # :agent_definition_id and :definition_checksum_at_spawn, or nil.
  # If the slug is not found in the DB, syncs the relevant directory first and retries.
  defp resolve_agent_definition(nil, _project_id, _project_path), do: nil
  defp resolve_agent_definition("", _project_id, _project_path), do: nil

  defp resolve_agent_definition(slug, project_id, project_path) do
    project_id = ToolHelpers.parse_int(project_id)
    case lookup_definition(slug, project_id) do
      {:ok, defn} ->
        %{agent_definition_id: defn.id, definition_checksum_at_spawn: defn.checksum}

      {:error, :not_found} ->
        Logger.debug("resolve_agent_definition: slug=#{slug} not in DB, syncing and retrying")
        sync_for_spawn(project_id, project_path)

        case lookup_definition(slug, project_id) do
          {:ok, defn} ->
            %{agent_definition_id: defn.id, definition_checksum_at_spawn: defn.checksum}

          {:error, :not_found} ->
            Logger.debug("resolve_agent_definition: slug=#{slug} not found after sync")
            nil
        end
    end
  end

  defp lookup_definition(slug, project_id) do
    if project_id do
      AgentDefinitions.resolve(slug, project_id)
    else
      AgentDefinitions.resolve_global(slug)
    end
  end

  defp sync_for_spawn(nil, _project_path), do: AgentDefinitions.sync_global()

  defp sync_for_spawn(project_id, project_path) do
    AgentDefinitions.sync_global()

    if project_path do
      AgentDefinitions.sync_project(project_id, project_path)
    end
  end

  defp maybe_put_definition(attrs, nil), do: attrs

  defp maybe_put_definition(attrs, definition_info) do
    Map.merge(attrs, definition_info)
  end
end
