defmodule EyeInTheSkyWeb.MCP.Tools.SpawnAgent do
  @moduledoc "Spawn a new Claude Code agent with Eye in the Sky integration"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :instructions, :string,
      required: true,
      description: "Task instructions for the agent"

    field :model, :string, description: "Model to use (haiku, sonnet, opus). Default: haiku"

    field :provider, :string, description: "AI provider (claude, codex). Default: claude"

    field :project_id, :integer,
      description: "Project ID to associate with the spawned agent and session"

    field :project_path, :string,
      description: "Working directory for the agent. Default: current directory"

    field :worktree, :string,
      description: "Git worktree name. Appends git push + PR instructions automatically."

    field :effort_level, :string, description: "Effort level override"

    field :parent_agent_id, :integer, description: "Parent agent ID for tracking spawn hierarchy"

    field :parent_session_id, :integer,
      description: "Parent session ID for tracking spawn hierarchy"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Claude.AgentManager

    opts = [
      instructions: params[:instructions],
      model: params[:model] || "haiku",
      agent_type: params[:provider] || "claude",
      project_id: params[:project_id],
      project_path: params[:project_path],
      description: params[:instructions],
      worktree: params[:worktree],
      effort_level: params[:effort_level],
      parent_agent_id: params[:parent_agent_id],
      parent_session_id: params[:parent_session_id]
    ]

    result =
      case AgentManager.create_agent(opts) do
        {:ok, %{agent: agent, session: session}} ->
          %{
            success: true,
            message: "Agent spawned",
            agent_id: agent.uuid,
            session_id: session.id,
            session_uuid: session.uuid
          }

        {:error, reason} ->
          %{success: false, message: "Spawn failed: #{inspect(reason)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
