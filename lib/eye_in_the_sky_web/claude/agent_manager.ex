defmodule EyeInTheSkyWeb.Claude.AgentManager do
  @moduledoc """
  Manages AgentWorker lifecycle - spawn on demand, lookup existing workers.

  Ensures only one AgentWorker per session and handles message routing.
  """

  require Logger

  alias EyeInTheSkyWeb.Claude.AgentWorker
  alias EyeInTheSkyWeb.{Sessions, Agents, Messages}

  def send_message(session_id, message, opts \\ []) do
    case lookup_or_start(session_id) do
      {:ok, _pid} ->
        # Check if session has prior messages for context
        has_messages = Messages.count_messages_for_session(session_id) > 0

        context = %{
          model: opts[:model] || "sonnet",
          has_messages: has_messages
        }

        AgentWorker.process_message(session_id, message, context)
        :ok

      {:error, reason} ->
        Logger.error("Failed to send message to agent: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp lookup_or_start(session_id) do
    case Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, session_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        start_agent_worker(session_id)
    end
  end

  defp start_agent_worker(session_id) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, agent} <- Agents.get_agent(session.agent_id) do
      project_path = agent.git_worktree_path || File.cwd!()

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
