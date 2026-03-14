defmodule EyeInTheSkyWebWeb.Api.V1.AgentController do
  use EyeInTheSkyWebWeb, :controller

  import EyeInTheSkyWebWeb.ControllerHelpers

  alias EyeInTheSkyWeb.{Agents, Claude.AgentManager}

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
      agents: Enum.map(agents, &format_agent/1)
    })
  end

  @doc """
  GET /api/v1/agents/:id - Get agent info.
  """
  def show(conn, %{"id" => id}) do
    result =
      case Integer.parse(id) do
        {int_id, ""} -> Agents.get_agent(int_id)
        _ -> Agents.get_agent_by_uuid(id)
      end

    case result do
      {:ok, agent} -> json(conn, %{success: true, agent: format_agent(agent)})
      _ -> conn |> put_status(:not_found) |> json(%{error: "Agent not found"})
    end
  end

  @doc """
  POST /api/v1/agents - Spawn a new Claude Code agent.
  Body: instructions, model, project_path, parent_agent_id, parent_session_id
  """
  def create(conn, params) do
    if is_nil(params["instructions"]) or params["instructions"] == "" do
      conn |> put_status(:bad_request) |> json(%{error: "instructions is required"})
    else
      opts = [
        instructions: params["instructions"],
        model: params["model"] || "haiku",
        project_path: params["project_path"],
        description: params["instructions"],
        parent_agent_id: params["parent_agent_id"],
        parent_session_id: params["parent_session_id"]
      ]

      case AgentManager.create_agent(opts) do
        {:ok, %{agent: _agent, session: session}} ->
          conn
          |> put_status(:created)
          |> json(%{success: true, message: "Agent spawned", session_id: session.uuid})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Spawn failed: #{inspect(reason)}"})
      end
    end
  end

  defp format_agent(agent) do
    %{
      id: agent.id,
      uuid: agent.uuid,
      description: agent.description,
      status: agent.status,
      project_id: agent.project_id,
      project_name: agent.project_name
    }
  end

end
