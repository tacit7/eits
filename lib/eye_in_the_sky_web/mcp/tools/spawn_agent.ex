defmodule EyeInTheSkyWeb.MCP.Tools.SpawnAgent do
  @moduledoc "Spawn a new Claude Code agent with Eye in the Sky integration"

  use Anubis.Server.Component, type: :tool

  require Logger

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
      description: "Team name to join. Agent is registered as a member server-side immediately on spawn."

    field :member_name, :string,
      description: "Member alias within the team (e.g. 'researcher'). Required with team_name."

    field :agent, :string,
      description:
        "Agent name to use (e.g. 'test-runner'). Resolved from project/.claude/agents or ~/.claude/agents."
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Claude.AgentManager
    alias EyeInTheSkyWeb.Teams

    # Resolve team before spawning so we can inject team_id into instructions
    team =
      case params[:team_name] do
        nil -> nil
        name -> Teams.get_team_by_name(name)
      end

    instructions =
      case team do
        nil -> params[:instructions]
        t -> params[:instructions] <> "\n\n" <> build_team_context(t, params[:member_name])
      end

    opts = [
      instructions: instructions,
      model: params[:model] || "haiku",
      agent_type: params[:provider] || "claude",
      project_id: params[:project_id],
      project_path: params[:project_path],
      description: truncate_description(params[:instructions] || "Agent session", 250),
      worktree: params[:worktree],
      effort_level: params[:effort_level],
      parent_agent_id: params[:parent_agent_id],
      parent_session_id: params[:parent_session_id],
      agent: params[:agent]
    ]

    result =
      case AgentManager.create_agent(opts) do
        {:ok, %{agent: agent, session: session}} ->
          maybe_join_team(team, agent, session, params[:member_name])

          base = %{
            success: true,
            message: "Agent spawned",
            agent_id: agent.uuid,
            session_id: session.id,
            session_uuid: session.uuid
          }

          if team do
            Map.merge(base, %{team_id: team.id, team_name: team.name, member_name: params[:member_name]})
          else
            base
          end

        {:error, reason} ->
          %{success: false, message: "Spawn failed: #{inspect(reason)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  defp maybe_join_team(nil, _agent, _session, _name), do: :ok

  defp maybe_join_team(team, agent, session, member_name) do
    alias EyeInTheSkyWeb.Teams

    Teams.join_team(%{
      team_id: team.id,
      agent_id: agent.id,
      session_id: session.id,
      name: member_name || agent.uuid,
      role: member_name || "agent",
      status: "active"
    })
  end

  defp truncate_description(text, max_len) do
    if String.length(text) > max_len do
      Logger.warning("spawn_agent: instructions truncated from #{String.length(text)} to #{max_len} chars for description")
      String.slice(text, 0, max_len)
    else
      text
    end
  end

  defp build_team_context(team, member_name) do
    """
    ## Team Context
    You are member "#{member_name || "agent"}" of team "#{team.name}" (team_id: #{team.id}).
    You have been registered as a team member automatically.
    Use i-team-members with team_id: #{team.id} to discover your teammates.
    Use i-todo list with team_id: #{team.id} to see shared tasks and claim work.
    Use i-team-join with command: "status" to update your status (active/idle/done).
    """
  end
end
