defmodule EyeInTheSkyWebWeb.Api.V1.SpawnController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.Claude.AgentManager

  @doc """
  POST /api/v1/agents/spawn - Spawn a new Claude Code agent.
  Body: instructions, model (optional), project_path (optional),
        parent_agent_id (optional), parent_session_id (optional)
  """
  def spawn_agent(conn, params) do
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
end
