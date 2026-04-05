defmodule EyeInTheSkyWeb.Api.V1.AgentController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, Projects, Teams}
  alias EyeInTheSky.Agents.{AgentManager, SpawnValidator}
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  require Logger

  @doc """
  GET /api/v1/agents - List agents.
  Query params: project_id, status, limit (default 20)
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 20)

    agents =
      if params["project_id"] do
        Agents.list_agents_by_project(parse_int(params["project_id"], nil)) |> Enum.take(limit)
      else
        Agents.list_agents() |> Enum.take(limit)
      end

    agents =
      if params["status"] do
        Enum.filter(agents, &(&1.status == params["status"]))
      else
        agents
      end

    json(conn, %{
      success: true,
      agents: Enum.map(agents, &ApiPresenter.present_agent/1)
    })
  end

  @doc """
  GET /api/v1/agents/:id - Get agent info.
  """
  def show(conn, %{"id" => id}) do
    result =
      if int_id = parse_int(id), do: Agents.get_agent(int_id), else: Agents.get_agent_by_uuid(id)

    with {:ok, agent} <- result do
      json(conn, %{success: true, agent: ApiPresenter.present_agent(agent)})
    end
  end

  @doc """
  POST /api/v1/agents - Spawn a new Claude Code agent.
  Body: instructions, model, provider, project_path, project_id, name, member_name,
        parent_agent_id, parent_session_id, worktree, team_name
  """
  def create(conn, params) do
    with {:ok, params} <- SpawnValidator.validate(params),
         {:ok, project_id, project_name} <- Projects.resolve_project(params),
         {:ok, team} <- resolve_team(params) do
      params = Map.merge(params, %{"project_id" => project_id, "project_name" => project_name})
      instructions = apply_team_context(params["instructions"], team, params["member_name"])
      opts = build_spawn_opts(%{params | "instructions" => instructions}, team)

      case AgentManager.create_agent(opts) do
        {:ok, %{agent: agent, session: session}} ->
          maybe_join_team(team, agent, session, params["member_name"])

          conn
          |> put_status(:created)
          |> json(build_response(agent, session, team, params["member_name"]))

        {:error, :dirty_working_tree} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error_code: "dirty_working_tree",
            message:
              "project_path has uncommitted changes; commit or stash before spawning a worktree agent"
          })

        {:error, reason} ->
          Logger.error("Agent spawn failed: #{inspect(reason)}")

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error_code: "spawn_failed", message: "Agent could not be started"})
      end
    else
      {:error, code, message} ->
        conn |> put_status(:bad_request) |> json(%{error_code: code, message: message})

      error ->
        Logger.error("Unexpected validation error in spawn: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error_code: "internal_error", message: "An unexpected error occurred"})
    end
  end

  defp maybe_join_team(nil, _agent, _session, _name), do: :ok

  defp maybe_join_team(team, agent, session, member_name) do
    result =
      Teams.join_team(%{
        team_id: team.id,
        agent_id: agent.id,
        session_id: session.id,
        name: member_name || agent.uuid,
        role: member_name || "agent",
        status: "active"
      })

    case result do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Team join failed: agent_id=#{agent.id} team_id=#{team.id} reason=#{inspect(reason)}"
        )

        :ok

      _ ->
        :ok
    end
  end

  defp build_team_context(team, member_name) do
    """
    ## Team Context
    You are member "#{member_name || "agent"}" of team "#{team.name}" (team_id: #{team.id}).
    You have been registered as a team member automatically.

    ## EITS Command Protocol

    Use the eits CLI script for all EITS operations:

      eits tasks begin --title "<title>"
      eits tasks annotate <id> --body "..."
      eits tasks update <id> --state 4
      eits dm --to <session_uuid> --message "..."
      eits commits create --hash <hash>

    ## Task Completion
    When you finish a task, follow this sequence exactly:
    1. Annotate the task with a summary of what was done
    2. Mark it done (or move to in-review, state 4)
    3. DM the orchestrator session to report completion
    4. Run the `/i-update-status` slash command to commit work and update session tracking
    Do NOT skip any steps. The orchestrator needs to see what you did.
    """
  end

  defp resolve_team(params) do
    case params["team_name"] do
      name when name in [nil, ""] ->
        {:ok, nil}

      name ->
        case Teams.get_team_by_name(name) do
          nil -> {:error, "team_not_found", "team not found: #{name}"}
          team -> {:ok, team}
        end
    end
  end

  defp apply_team_context(instructions, nil, _member_name), do: instructions

  defp apply_team_context(instructions, team, member_name) do
    instructions <> "\n\n" <> build_team_context(team, member_name)
  end

  # Fix 2: accept name param, auto-generate from member_name+team or truncated instructions
  defp resolve_session_name(params, team) do
    name = params["name"]

    if name && String.trim(name) != "" do
      String.trim(name)
    else
      member_name = params["member_name"]
      team_name = team && team.name

      cond do
        member_name && team_name -> "#{member_name} @ #{team_name}"
        member_name -> member_name
        true -> String.slice(params["instructions"] || "Agent session", 0, 250)
      end
    end
  end

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

  defp build_response(agent, session, team, member_name) do
    base = %{
      success: true,
      message: "Agent spawned",
      agent_id: agent.uuid,
      session_id: session.id,
      session_uuid: session.uuid
    }

    if team do
      Map.merge(base, %{team_id: team.id, team_name: team.name, member_name: member_name})
    else
      base
    end
  end
end
