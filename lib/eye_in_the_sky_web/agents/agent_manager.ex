defmodule EyeInTheSkyWeb.Agents.AgentManager do
  @moduledoc """
  Manages AgentWorker lifecycle - spawn on demand, lookup existing workers.

  Ensures only one AgentWorker per session and handles message routing.
  """

  require Logger

  alias EyeInTheSkyWeb.Agents.InstructionBuilder
  alias EyeInTheSkyWeb.Claude.AgentWorker
  alias EyeInTheSkyWeb.Git.Worktrees
  alias EyeInTheSkyWeb.{Agents, Messages, Sessions}

  @registry EyeInTheSkyWeb.Claude.AgentRegistry
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

      case send_message(session.id, instructions,
             model: opts[:model],
             effort_level: opts[:effort_level],
             max_budget_usd: opts[:max_budget_usd],
             worktree: opts[:worktree],
             agent: opts[:agent],
             eits_workflow: opts[:eits_workflow]
           ) do
        {:ok, _admission} ->
          Logger.info(
            "✅ create_agent: initial message sent successfully to session.id=#{session.id}"
          )

          {:ok, %{agent: agent, session: session}}

        {:error, reason} ->
          Logger.error(
            "❌ create_agent: initial message failed for session.id=#{session.id} - #{inspect(reason)}"
          )

          {:error, {:send_failed, reason}}
      end
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

    with {:ok, worktree_path} <- resolve_worktree_path(opts) do
      insert_agent_and_session(%{
        agent_uuid: agent_uuid,
        provider: provider,
        session_uuid: session_uuid,
        description: description,
        project_id: project_id,
        worktree_path: worktree_path,
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
    # Inherit project_id from parent session if not explicitly provided
    case opts[:project_id] do
      nil ->
        case opts[:parent_session_id] do
          nil ->
            nil

          parent_id ->
            case Sessions.get_session(parent_id) do
              {:ok, parent} -> parent.project_id
              _ -> nil
            end
        end

      id ->
        id
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
            Logger.error(
              "create_agent: git worktree setup failed for #{wt}: #{inspect(reason)}"
            )

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
         opts: opts
       }) do
    with {:ok, agent} <-
           Agents.create_agent(%{
             uuid: agent_uuid,
             agent_type: opts[:agent_type] || "claude",
             project_id: project_id,
             project_name: opts[:project_name],
             status: "working",
             description: description,
             git_worktree_path: worktree_path,
             parent_agent_id: opts[:parent_agent_id],
             parent_session_id: opts[:parent_session_id]
           }),
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
             started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
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

        has_messages = Messages.has_inbound_reply?(session_id, provider)

        context = %{
          model: opts[:model],
          effort_level: opts[:effort_level],
          has_messages: has_messages,
          channel_id: opts[:channel_id],
          thinking_budget: opts[:thinking_budget],
          max_budget_usd: opts[:max_budget_usd],
          agent: opts[:agent],
          eits_workflow: opts[:eits_workflow]
        }

        case GenServer.call(pid, {:submit_message, message, context}) do
          {:ok, admission} ->
            Logger.debug(
              "send_message: #{admission} for session_id=#{session_id}"
            )

            {:ok, admission}

          {:error, reason} = error ->
            Logger.warning(
              "send_message: rejected for session_id=#{session_id} - #{inspect(reason)}"
            )

            error
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
    case Registry.lookup(@registry, {:agent, session_id}) do
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
         {:ok, agent} <- Agents.get_agent(session.agent_id) do
      project_path_from_project = if agent.project, do: agent.project.path, else: nil

      resolved_path =
        session.git_worktree_path ||
          agent.git_worktree_path ||
          project_path_from_project

      project_path =
        if is_nil(resolved_path) do
          fallback = File.cwd!()

          Logger.error(
            "start_agent_worker: no project_path for session.id=#{session_id}; " <>
              "session.git_worktree_path=#{inspect(session.git_worktree_path)}, " <>
              "agent.git_worktree_path=#{inspect(agent.git_worktree_path)}, " <>
              "project.path=#{inspect(project_path_from_project)} — falling back to cwd=#{fallback}"
          )

          fallback
        else
          resolved_path
        end

      Logger.info(
        "✅ start_agent_worker: loaded session.uuid=#{session.uuid}, agent.id=#{agent.id}, project_path=#{project_path}"
      )

      case normalize_provider(session.provider) do
        nil ->
          {:error, {:unsupported_provider, session.provider}}

        provider ->
          # Ensure session has a UUID — Codex sessions created from the UI may not have one
          session =
            if is_nil(session.uuid) or session.uuid == "" do
              uuid = Ecto.UUID.generate()
              Logger.info("start_agent_worker: generating UUID=#{uuid} for session.id=#{session.id}")
              {:ok, updated} = Sessions.update_session(session, %{uuid: uuid})
              updated
            else
              session
            end

          opts = [
            session_id: session.id,
            provider_conversation_id: session.uuid,
            agent_id: agent.id,
            project_id: session.project_id,
            project_path: project_path,
            provider: provider,
            worktree: extra_opts[:worktree]
          ]

          case DynamicSupervisor.start_child(
                 EyeInTheSkyWeb.Claude.AgentSupervisor,
                 {AgentWorker, opts}
               ) do
            {:ok, pid} ->
              Logger.info(
                "✅ start_agent_worker: AgentWorker started for session.id=#{session_id}, pid=#{inspect(pid)}"
              )

              {:ok, pid, provider}

            {:error, {:already_started, pid}} ->
              Logger.info(
                "start_agent_worker: worker already started for session.id=#{session_id}, pid=#{inspect(pid)}"
              )

              {:ok, pid, provider}

            {:error, reason} = error ->
              Logger.error(
                "❌ start_agent_worker: failed to start AgentWorker for session.id=#{session_id} - #{inspect(reason)}"
              )

              error
          end
      end
    else
      {:error, reason} ->
        Logger.error(
          "❌ start_agent_worker: failed to load session/agent for session.id=#{session_id} - #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp normalize_provider(provider) when provider in @supported_providers, do: provider
  defp normalize_provider(_provider), do: nil
end
