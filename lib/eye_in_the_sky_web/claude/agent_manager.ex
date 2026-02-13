defmodule EyeInTheSkyWeb.Claude.AgentManager do
  @moduledoc """
  Manages AgentWorker lifecycle - spawn on demand, lookup existing workers.

  Ensures only one AgentWorker per session and handles message routing.
  """

  require Logger

  alias EyeInTheSkyWeb.Claude.AgentWorker
  alias EyeInTheSkyWeb.{Sessions, Agents, Messages}

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

    with {:ok, agent} <-
           Agents.create_agent(%{
             uuid: agent_uuid,
             agent_type: opts[:agent_type] || "claude",
             project_id: opts[:project_id],
             status: "active",
             description: description
           }),
         {:ok, session} <-
           Sessions.create_session(%{
             uuid: session_uuid,
             agent_id: agent.id,
             name: description,
             description: "session-id #{session_uuid} agent-id #{agent_uuid}",
             model: opts[:model],
             provider: "claude",
             git_worktree_path: opts[:project_path],
             started_at: DateTime.utc_now() |> DateTime.to_iso8601()
           }) do
      # Start AgentWorker and send the initial message
      instructions = opts[:instructions] || description

      send_message(session.id, instructions,
        model: opts[:model],
        effort_level: opts[:effort_level]
      )

      {:ok, %{agent: agent, session: session}}
    else
      {:error, reason} ->
        Logger.error("Failed to create agent: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def send_message(session_id, message, opts \\ []) do
    case lookup_or_start(session_id) do
      {:ok, _pid} ->
        # Check if session has prior messages for context
        has_messages = Messages.count_messages_for_session(session_id) > 0

        context = %{
          model: opts[:model],
          effort_level: opts[:effort_level],
          has_messages: has_messages,
          channel_id: opts[:channel_id]
        }

        AgentWorker.process_message(session_id, message, context)
        :ok

      {:error, reason} ->
        Logger.error("Failed to send message to agent: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp lookup_or_start(session_id) do
    name = String.to_atom("agent_worker_#{session_id}")

    case Process.whereis(name) do
      nil ->
        start_agent_worker(session_id)

      pid ->
        {:ok, pid}
    end
  end

  defp start_agent_worker(session_id) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, agent} <- Agents.get_agent(session.agent_id) do
      project_path = session.git_worktree_path || agent.git_worktree_path || File.cwd!()

      opts = [
        session_id: session.id,
        session_uuid: session.uuid,
        agent_id: agent.id,
        project_path: project_path
      ]

      DynamicSupervisor.start_child(
        EyeInTheSkyWeb.Claude.AgentSupervisor,
        {AgentWorker, opts}
      )
    else
      {:error, reason} ->
        Logger.error("Failed to load session/agent: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
