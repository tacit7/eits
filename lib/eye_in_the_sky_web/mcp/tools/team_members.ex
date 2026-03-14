defmodule EyeInTheSkyWeb.MCP.Tools.TeamMembers do
  @moduledoc "List team members for peer discovery"

  use Anubis.Server.Component, type: :tool

  alias EyeInTheSkyWeb.MCP.Tools.{Helpers, ResponseHelper}
  alias EyeInTheSkyWeb.Teams

  schema do
    field :team_id, :integer, description: "Team ID"
    field :team_name, :string, description: "Team name (alternative to team_id)"
  end

  @impl true
  def execute(params, frame) do
    team = Helpers.resolve_team(params)

    result =
      case team do
        nil ->
          %{success: false, message: "Team not found"}

        team ->
          members =
            Teams.list_members(team.id)
            |> Enum.map(fn m ->
              %{
                name: m.name,
                role: m.role,
                status: m.status,
                agent_id: m.agent_id,
                session_id: m.session_id,
                joined_at: m.joined_at,
                last_activity_at: m.last_activity_at
              }
            end)

          %{
            success: true,
            team_id: team.id,
            team_name: team.name,
            members: members
          }
      end

    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end
end
