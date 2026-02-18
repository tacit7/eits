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
    session_uuid = Ecto.UUID.generate()

    description = opts[:description] || "Agent session"

    Logger.info(
      "📝 create_agent: agent_uuid=#{agent_uuid}, session_uuid=#{session_uuid}, model=#{opts[:model]}, project_id=#{opts[:project_id]}"
    )

    provider = if opts[:agent_type] == "codex", do: "codex", else: "claude"

    with {:ok, agent} <-
           Agents.create_agent(%{
             uuid: agent_uuid,
             agent_type: opts[:agent_type] || "claude",
             project_id: opts[:project_id],
             status: "working",
             description: description
           }),
         {:ok, session} <-
           Sessions.create_session(%{
             uuid: session_uuid,
             agent_id: agent.id,
             name: description,
             description: "session-id #{session_uuid} agent-id #{agent_uuid}",
             model: opts[:model],
             provider: provider,
             git_worktree_path: opts[:project_path],
             started_at: DateTime.utc_now() |> DateTime.to_iso8601()
           }) do
      Logger.info(
        "✅ create_agent: DB records created - agent.id=#{agent.id}, session.id=#{session.id}, session_uuid=#{session.uuid}"
      )

      instructions = opts[:instructions] || description

      Logger.info("📤 create_agent: sending initial message to session.id=#{session.id}")

      case send_message(session.id, instructions,
             model: opts[:model],
             effort_level: opts[:effort_level]
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

    case lookup_or_start(session_id) do
      {:ok, pid} ->
        Logger.debug(
          "send_message: worker found/started for session_id=#{session_id}, pid=#{inspect(pid)}"
        )

        provider = resolve_provider(session_id, opts)
        has_messages = Messages.has_inbound_reply?(session_id, provider)

        context = %{
          model: opts[:model],
          effort_level: opts[:effort_level],
          has_messages: has_messages,
          channel_id: opts[:channel_id]
        }

        case AgentWorker.process_message(session_id, message, context) do
          :ok ->
            Logger.debug("send_message: message queued for session_id=#{session_id}")
            :ok

          {:error, reason} ->
            Logger.error(
              "❌ send_message: failed to queue message for session_id=#{session_id} - #{inspect(reason)}"
            )

            {:error, reason}
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

  defp lookup_or_start(session_id) do
    case Registry.lookup(@registry, {:agent, session_id}) do
      [{pid, _}] ->
        if Process.alive?(pid) do
          Logger.debug(
            "lookup_or_start: found existing worker for session_id=#{session_id}, pid=#{inspect(pid)}"
          )

          {:ok, pid}
        else
          start_agent_worker(session_id)
        end

      [] ->
        Logger.info(
          "🔍 lookup_or_start: no worker found for session_id=#{session_id}, starting new worker"
        )

        start_agent_worker(session_id)
    end
  end

  defp start_agent_worker(session_id) do
    Logger.info("🚀 start_agent_worker: loading session.id=#{session_id}")

    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, agent} <- Agents.get_agent(session.agent_id) do
      project_path_from_project = if agent.project, do: agent.project.path, else: nil

      project_path =
        session.git_worktree_path ||
          agent.git_worktree_path ||
          project_path_from_project ||
          File.cwd!()

      if is_nil(session.git_worktree_path) && is_nil(agent.git_worktree_path) &&
           is_nil(project_path_from_project) do
        Logger.warning(
          "start_agent_worker: no explicit project_path for session.id=#{session_id}; defaulting to cwd=#{project_path}"
        )
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
        provider: provider
      ]

      case DynamicSupervisor.start_child(
             EyeInTheSkyWeb.Claude.AgentSupervisor,
             {AgentWorker, opts}
           ) do
        {:ok, pid} = result ->
          Logger.info(
            "✅ start_agent_worker: AgentWorker started for session.id=#{session_id}, pid=#{inspect(pid)}"
          )

          result

        {:error, {:already_started, pid}} ->
          Logger.info(
            "start_agent_worker: worker already started for session.id=#{session_id}, pid=#{inspect(pid)}"
          )

          {:ok, pid}

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

  defp resolve_provider(session_id, opts) do
    opts[:provider]
    |> normalize_provider()
    |> case do
      nil ->
        case Sessions.get_session(session_id) do
          {:ok, session} -> normalize_provider(session.provider) || @default_provider
          _ -> @default_provider
        end

      provider ->
        provider
    end
  end

  defp normalize_provider(provider) when provider in @supported_providers, do: provider
  defp normalize_provider(_provider), do: nil
end
