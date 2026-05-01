defmodule EyeInTheSkyWeb.Api.V1.AgentController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Agents.{AgentManager, SpawnValidator}
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  require Logger

  @doc """
  GET /api/v1/agents - List agents.
  Query params: project_id, status, limit (default 20), active_since (ISO8601)
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 20)

    with {:ok, agents} <- resolve_agents(params, limit) do
      json(conn, %{
        success: true,
        agents: Enum.map(agents, &ApiPresenter.present_agent/1)
      })
    else
      {:error, :invalid_since} ->
        conn |> put_status(:bad_request) |> json(%{error: "Invalid active_since datetime"})
    end
  end

  defp resolve_agents(%{"active_since" => since_str} = params, limit) do
    case DateTime.from_iso8601(since_str) do
      {:ok, since_dt, _} -> {:ok, Agents.list_agents_active_since(since_dt, build_query_opts(params, limit))}
      _ -> {:error, :invalid_since}
    end
  end

  defp resolve_agents(%{"project_id" => project_id} = params, limit) do
    {:ok, Agents.list_agents_by_project(parse_int(project_id, nil), build_query_opts(params, limit))}
  end

  defp resolve_agents(params, limit) do
    {:ok, Agents.list_agents(build_query_opts(params, limit))}
  end

  defp build_query_opts(params, limit) do
    opts = [limit: limit]
    if params["status"], do: [status: params["status"]] ++ opts, else: opts
  end

  @doc """
  GET /api/v1/agents/:id - Get agent info.
  """
  def show(conn, %{"id" => id}) do
    result =
      if int_id = parse_int(id), do: Agents.get_agent(int_id), else: Agents.get_agent_by_uuid(id)

    case result do
      {:ok, agent} ->
        json(conn, %{success: true, agent: ApiPresenter.present_agent(agent)})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Agent not found"})
    end
  end

  @doc """
  POST /api/v1/agents - Spawn a new Claude Code agent.
  Body: instructions, model, provider, project_path, project_id, name, member_name,
        parent_agent_id, parent_session_id, worktree, team_name
  """
  def create(conn, params) do
    with {:ok, params} <- SpawnValidator.validate(params) do
      case AgentManager.spawn_agent(params) do
        {:ok, %{agent: agent, session: session, team: team, member_name: member_name}} ->
          conn
          |> put_status(:created)
          |> json(build_response(agent, session, team, member_name))

        {:error, :dirty_working_tree} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error_code: "dirty_working_tree",
            message:
              "project_path has uncommitted changes; commit or stash before spawning a worktree agent"
          })

        {:error, code, message} when is_binary(code) ->
          conn |> put_status(:bad_request) |> json(%{error_code: code, message: message})

        {:error, {:worktree_setup_failed, reason}} ->
          msg = if is_binary(reason), do: String.trim(reason), else: inspect(reason)

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error_code: "worktree_setup_failed",
            message: "Git worktree setup failed: #{msg}"
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
