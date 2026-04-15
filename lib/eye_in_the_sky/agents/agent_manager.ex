defmodule EyeInTheSky.Agents.AgentManager do
  @moduledoc """
  Manages AgentWorker lifecycle - spawn on demand, lookup existing workers.

  Ensures only one AgentWorker per session and handles message routing.
  """

  require Logger

  alias EyeInTheSky.{Agents, Projects, Teams}
  alias EyeInTheSky.Agents.AgentManager.RecordBuilder
  alias EyeInTheSky.Agents.AgentManager.SessionBridge
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
         {:ok, team} <- resolve_spawn_team(params["team_name"]) do
      params = Map.merge(params, %{"project_id" => project_id, "project_name" => project_name})
      instructions = apply_team_context(params["instructions"], team, params["member_name"])
      opts = build_spawn_opts(%{params | "instructions" => instructions}, team)

      case create_agent(opts) do
        {:ok, %{agent: agent, session: session}} ->
          case maybe_join_team(team, agent, session, params["member_name"]) do
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

  defp resolve_spawn_team(nil), do: {:ok, nil}
  defp resolve_spawn_team(""), do: {:ok, nil}

  defp resolve_spawn_team(name) do
    case Teams.get_team_by_name(name) do
      {:error, :not_found} -> {:error, "team_not_found", "team not found: #{name}"}
      {:ok, team} -> {:ok, team}
    end
  end

  defp apply_team_context(instructions, nil, _member_name), do: instructions

  defp apply_team_context(instructions, team, member_name) do
    instructions <> "\n\n" <> build_team_context(team, member_name)
  end

  defp build_team_context(team, member_name) do
    EyeInTheSky.Agents.InstructionTemplates.team_context(team, member_name)
  end

  # Name resolution priority:
  # 1. Explicit "name" param (trimmed, non-empty)
  # 2. "member_name @ team_name" when both present
  # 3. "member_name" alone
  # 4. First 250 chars of instructions (or "Agent session" fallback)
  defp resolve_session_name(%{"name" => name} = params, team)
       when is_binary(name) and name != "" do
    case String.trim(name) do
      "" -> resolve_session_name(Map.delete(params, "name"), team)
      trimmed -> trimmed
    end
  end

  defp resolve_session_name(params, %{name: team_name})
       when is_binary(team_name) do
    member = params["member_name"]

    if member,
      do: "#{member} @ #{team_name}",
      else: String.slice(params["instructions"] || "Agent session", 0, 250)
  end

  defp resolve_session_name(%{"member_name" => member}, _team) when is_binary(member),
    do: member

  defp resolve_session_name(params, _team),
    do: String.slice(params["instructions"] || "Agent session", 0, 250)

  defp build_spawn_opts(params, team) do
    name = resolve_session_name(params, team)

    [
      instructions: params["instructions"],
      model: params["model"],
      agent_type: params["provider"] || "claude",
      project_id: params["project_id"],
      project_name: params["project_name"],
      project_path: params["project_path"],
      name: name,
      description: name,
      worktree: params["worktree"],
      effort_level: params["effort_level"],
      parent_agent_id: params["parent_agent_id"],
      parent_session_id: params["parent_session_id"],
      agent: params["agent"],
      bypass_sandbox: params["bypass_sandbox"] == true
    ]
  end

  defp maybe_join_team(nil, _agent, _session, _name), do: :ok

  defp maybe_join_team(team, agent, session, member_name) do
    case Teams.join_team(%{
           team_id: team.id,
           agent_id: agent.id,
           session_id: session.id,
           name: member_name || agent.uuid,
           role: member_name || "agent",
           status: "active"
         }) do
      {:ok, member} ->
        {:ok, member}

      {:error, reason} ->
        Logger.warning(
          "Team join failed: agent_id=#{agent.id} session_id=#{session.id} team_id=#{team.id} member_name=#{inspect(member_name)} reason=#{inspect(reason)}"
        )

        {:error, {:team_join_failed, reason}}
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
