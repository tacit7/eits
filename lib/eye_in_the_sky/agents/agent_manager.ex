defmodule EyeInTheSky.Agents.AgentManager do
  @moduledoc """
  Manages AgentWorker lifecycle - spawn on demand, lookup existing workers.

  Ensures only one AgentWorker per session and handles message routing.
  """

  require Logger

  alias EyeInTheSky.{Agents, Projects}
  alias EyeInTheSky.Agents.AgentManager.RecordBuilder
  alias EyeInTheSky.Agents.AgentManager.SessionBridge
  alias EyeInTheSky.Agents.AgentManager.SpawnParams
  alias EyeInTheSky.Agents.AgentManager.SpawnTeamContext
  alias EyeInTheSky.Claude.AgentWorker

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
    with {:ok, %{agent: agent, session: session}} <- RecordBuilder.create_records(opts) do
      instructions = EyeInTheSky.Agents.InstructionBuilder.build(opts)

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

  @doc """
  Orchestrates agent spawning from validated HTTP params.

  Resolves project and team, applies team context to instructions,
  creates the agent, and joins the team if applicable.

  Returns `{:ok, %{agent: agent, session: session, team: team, member_name: member_name}}`
  or `{:error, code, message}` for validation errors, or `{:error, reason}` for spawn failures.
  """
  def spawn_agent(params) do
    with {:ok, project_id, project_name} <- Projects.resolve_project(params),
         {:ok, team} <- SpawnTeamContext.resolve_team(params["team_name"]) do
      params = Map.merge(params, %{"project_id" => project_id, "project_name" => project_name})
      instructions = SpawnTeamContext.apply_context(params["instructions"], team, params["member_name"])
      opts = SpawnParams.build(%{params | "instructions" => instructions}, team)

      case create_agent(opts) do
        {:ok, %{agent: agent, session: session}} ->
          case SpawnTeamContext.maybe_join(team, agent, session, params["member_name"]) do
            :ok ->
              {:ok,
               %{agent: agent, session: session, team: team, member_name: params["member_name"]}}

            {:ok, _member} ->
              {:ok,
               %{agent: agent, session: session, team: team, member_name: params["member_name"]}}

            {:error, reason} ->
              {:error, reason}
          end

        error ->
          error
      end
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

    case SessionBridge.ensure_worker_running(session_id, opts) do
      {:ok, pid, provider} ->
        Logger.debug(
          "send_message: worker found/started for session_id=#{session_id}, pid=#{inspect(pid)}"
        )

        context = EyeInTheSky.Agents.RuntimeContext.build(session_id, provider, opts)

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
            Logger.error(
              "send_message: worker exit for session_id=#{session_id} - #{inspect(reason)}"
            )

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

end
