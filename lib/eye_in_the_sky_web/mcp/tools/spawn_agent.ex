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

    field :team_name, :string,
      description: "Team name to auto-join after spawn. Agent will call i-team-join on startup."

    field :member_name, :string,
      description: "Member alias within the team (e.g. 'researcher'). Required with team_name."
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Claude.AgentManager

    team_instructions = build_team_instructions(params)

    instructions =
      if team_instructions do
        params[:instructions] <> "\n\n" <> team_instructions
      else
        params[:instructions]
      end

    opts = [
      instructions: instructions,
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
          base = %{
            success: true,
            message: "Agent spawned",
            agent_id: agent.uuid,
            session_id: session.id,
            session_uuid: session.uuid
          }

          if params[:team_name] do
            Map.merge(base, %{team_name: params[:team_name], member_name: params[:member_name]})
          else
            base
          end

        {:error, reason} ->
          %{success: false, message: "Spawn failed: #{inspect(reason)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  defp build_team_instructions(%{team_name: team_name, member_name: name})
       when is_binary(team_name) and is_binary(name) do
    """
    ## Team Context
    You are part of team "#{team_name}" with the role/name "#{name}".
    On startup, call i-team-join with team_name: "#{team_name}", name: "#{name}".
    Use i-team-members to discover your teammates.
    Use i-todo with team_id to list shared team tasks and claim work.
    When you complete work, update your status with i-team-join (status: "done").
    """
  end

  defp build_team_instructions(_), do: nil
end
