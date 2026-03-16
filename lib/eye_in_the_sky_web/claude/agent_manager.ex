defmodule EyeInTheSkyWeb.Claude.AgentManager do
  @moduledoc """
  Manages AgentWorker lifecycle - spawn on demand, lookup existing workers.

  Ensures only one AgentWorker per session and handles message routing.
  """

  require Logger

  alias EyeInTheSkyWeb.Claude.AgentWorker
  alias EyeInTheSkyWeb.{Agents, Messages, Sessions}

  @registry EyeInTheSkyWeb.Claude.AgentRegistry
  @default_provider "claude"
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
    agent_uuid = Ecto.UUID.generate()
    provider = if opts[:agent_type] == "codex", do: "codex", else: "claude"

    # For codex sessions, leave uuid null — Codex sets it via i-session start.
    # For claude sessions, pre-generate so the worker can reference it immediately.
    session_uuid = if provider == "codex", do: nil, else: opts[:session_uuid] || Ecto.UUID.generate()

    description = opts[:description] || "Agent session"

    # Inherit project_id from parent session if not explicitly provided
    project_id =
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

    Logger.info(
      "📝 create_agent: agent_uuid=#{agent_uuid}, session_uuid=#{inspect(session_uuid)}, model=#{opts[:model]}, project_id=#{project_id}"
    )

    with {:ok, agent} <-
           Agents.create_agent(%{
             uuid: agent_uuid,
             agent_type: opts[:agent_type] || "claude",
             project_id: project_id,
             status: "working",
             description: description,
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
             git_worktree_path: opts[:project_path],
             started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
             parent_agent_id: opts[:parent_agent_id],
             parent_session_id: opts[:parent_session_id]
           }) do
      Logger.info(
        "✅ create_agent: DB records created - agent.id=#{agent.id}, session.id=#{session.id}, session_uuid=#{session.uuid}"
      )

      instructions =
        case opts[:worktree] do
          nil ->
            opts[:instructions] || description

          worktree ->
            base = opts[:instructions] || description
            branch = "worktree-#{worktree}"

            base <>
              """


              ---
              When your work is complete:
              1. Commit all changes with a clear message describing what was done.
              2. Push your branch: git push gitea #{branch}
              3. Create a pull request: tea pr create --login claude --repo eits-web --base main --head #{branch} --title "<your task summary>" --description "<what you did and why>"
              4. Call i-end-session to mark your session complete.
              """
        end

      Logger.info("📤 create_agent: sending initial message to session.id=#{session.id}")

      case send_message(session.id, instructions,
             model: opts[:model],
             effort_level: opts[:effort_level],
             max_budget_usd: opts[:max_budget_usd],
             worktree: opts[:worktree],
             agent: opts[:agent],
             eits_workflow: opts[:eits_workflow]
           ) do
        :ok ->
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

        GenServer.cast(pid, {:process_message, message, context})
        Logger.debug("send_message: message queued for session_id=#{session_id}")
        :ok

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
      [{pid, _}] ->
        if Process.alive?(pid) do
          Logger.debug(
            "lookup_or_start: found existing worker for session_id=#{session_id}, pid=#{inspect(pid)}"
          )

          provider = normalize_provider(extra_opts[:provider]) || @default_provider
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

      provider = normalize_provider(session.provider) || "claude"

      opts = [
        session_id: session.id,
        session_uuid: session.uuid,
        agent_id: agent.id,
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
