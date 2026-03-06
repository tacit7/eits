defmodule EyeInTheSkyWeb.MCP.Tools.SpawnAgent do
  @moduledoc "Spawn a new Claude Code agent with Eye in the Sky integration"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :instructions, :string,
      required: true,
      description: "Task instructions for the agent (required)"

    field :model, :string, description: "Model to use (haiku, sonnet, opus). Default: haiku"
    field :project_path, :string, description: "Working directory. Default: current directory"
    field :skip_permissions, :boolean, description: "Skip permission prompts (default: true)"
    field :background, :boolean, description: "Run agent in background (default: false)"
    field :parent_agent_id, :string, description: "Parent agent ID for tracking hierarchy"
    field :parent_session_id, :string, description: "Parent session ID for tracking hierarchy"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Claude.AgentManager

    opts = [
      instructions: params[:instructions],
      model: params[:model] || "haiku",
      project_path: params[:project_path],
      description: params[:instructions],
      parent_agent_id: params[:parent_agent_id],
      parent_session_id: params[:parent_session_id]
    ]

    result =
      case AgentManager.create_agent(opts) do
        {:ok, %{agent: _agent, session: session}} ->
          %{
            success: true,
            message: "Agent spawned",
            session_id: session.uuid
          }

        {:error, reason} ->
          %{success: false, message: "Spawn failed: #{inspect(reason)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
