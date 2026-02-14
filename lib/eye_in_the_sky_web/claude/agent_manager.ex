defmodule EyeInTheSkyWeb.Claude.AgentManager do
  @moduledoc """
  Manages AgentWorker lifecycle - spawn on demand, lookup existing workers.

  Ensures only one AgentWorker per session and handles message routing.
  """

  require Logger

  alias EyeInTheSkyWeb.Claude.AgentWorker
  alias EyeInTheSkyWeb.{Agents, ChatAgents, Messages}

  @registry EyeInTheSkyWeb.Claude.AgentRegistry

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
    session_uuid = Ecto.UUID.generate()

    description = opts[:description] || "Agent session"

    Logger.info("📝 create_agent: agent_uuid=#{agent_uuid}, session_uuid=#{session_uuid}, model=#{opts[:model]}, project_id=#{opts[:project_id]}")

    with {:ok, agent} <-
           ChatAgents.create_chat_agent(%{
             uuid: agent_uuid,
             agent_type: opts[:agent_type] || "claude",
             project_id: opts[:project_id],
             status: "active",
             description: description
           }),
         {:ok, session} <-
           Agents.create_execution_agent(%{
             uuid: session_uuid,
             agent_id: agent.id,
             name: description,
             description: "session-id #{session_uuid} agent-id #{agent_uuid}",
             model: opts[:model],
             provider: "claude",
             git_worktree_path: opts[:project_path],
             started_at: DateTime.utc_now() |> DateTime.to_iso8601()
           }) do
      Logger.info("✅ create_agent: DB records created - agent.id=#{agent.id}, session.id=#{session.id}, session_uuid=#{session.uuid}")

      instructions = opts[:instructions] || description

      Logger.info("📤 create_agent: sending initial message to session.id=#{session.id}")

      case send_message(session.id, instructions,
             model: opts[:model],
             effort_level: opts[:effort_level]
           ) do
        :ok ->
          Logger.info("✅ create_agent: initial message sent successfully to session.id=#{session.id}")
          {:ok, %{agent: agent, session: session}}

        {:error, reason} ->
          Logger.error("❌ create_agent: initial message failed for session.id=#{session.id} - #{inspect(reason)}")
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

  def send_message(session_id, message, opts \\ []) do
    Logger.debug("send_message: session_id=#{session_id}, message_length=#{String.length(message)}")

    case lookup_or_start(session_id) do
      {:ok, pid} ->
        Logger.debug("send_message: worker found/started for session_id=#{session_id}, pid=#{inspect(pid)}")
        has_messages = Messages.count_messages_for_session(session_id) > 0

        context = %{
          model: opts[:model],
          effort_level: opts[:effort_level],
          has_messages: has_messages,
          channel_id: opts[:channel_id]
        }

        AgentWorker.process_message(session_id, message, context)
        Logger.debug("send_message: message queued for session_id=#{session_id}")
        :ok

      {:error, reason} ->
        Logger.error("❌ send_message: failed to lookup/start worker for session_id=#{session_id} - #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp lookup_or_start(session_id) do
    case Registry.lookup(@registry, {:agent, session_id}) do
      [{pid, _}] ->
        Logger.debug("lookup_or_start: found existing worker for session_id=#{session_id}, pid=#{inspect(pid)}")
        {:ok, pid}

      [] ->
        Logger.info("🔍 lookup_or_start: no worker found for session_id=#{session_id}, starting new worker")
        start_agent_worker(session_id)
    end
  end

  defp start_agent_worker(session_id) do
    Logger.info("🚀 start_agent_worker: loading session.id=#{session_id}")

    with {:ok, session} <- Agents.get_execution_agent(session_id),
         {:ok, agent} <- ChatAgents.get_chat_agent(session.agent_id) do
      project_path = session.git_worktree_path || agent.git_worktree_path || File.cwd!()

      Logger.info("✅ start_agent_worker: loaded session.uuid=#{session.uuid}, agent.id=#{agent.id}, project_path=#{project_path}")

      opts = [
        session_id: session.id,
        session_uuid: session.uuid,
        agent_id: agent.id,
        project_path: project_path
      ]

      case DynamicSupervisor.start_child(
             EyeInTheSkyWeb.Claude.AgentSupervisor,
             {AgentWorker, opts}
           ) do
        {:ok, pid} = result ->
          Logger.info("✅ start_agent_worker: AgentWorker started for session.id=#{session_id}, pid=#{inspect(pid)}")
          result

        {:error, reason} = error ->
          Logger.error("❌ start_agent_worker: failed to start AgentWorker for session.id=#{session_id} - #{inspect(reason)}")
          error
      end
    else
      {:error, reason} ->
        Logger.error("❌ start_agent_worker: failed to load session/agent for session.id=#{session_id} - #{inspect(reason)}")
        {:error, reason}
    end
  end
end
