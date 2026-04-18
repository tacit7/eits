defmodule EyeInTheSky.Agents.AgentManager.SpawnTeamContext do
  @moduledoc "Resolves team membership and injects team context into spawn instructions."

  require Logger

  alias EyeInTheSky.Teams

  def resolve_team(nil), do: {:ok, nil}
  def resolve_team(""), do: {:ok, nil}

  def resolve_team(name) do
    case Teams.get_team_by_name(name) do
      {:error, :not_found} -> {:error, "team_not_found", "team not found: #{name}"}
      {:ok, team} -> {:ok, team}
    end
  end

  def apply_context(instructions, nil, _member_name), do: instructions

  def apply_context(instructions, team, member_name) do
    instructions <> "\n\n" <> EyeInTheSky.Agents.InstructionTemplates.team_context(team, member_name)
  end

  def maybe_join(nil, _agent, _session, _name), do: :ok

  def maybe_join(team, agent, session, member_name) do
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
end
