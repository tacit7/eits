defmodule EyeInTheSkyWeb.MCP.Tools.TeamMembers do
  @moduledoc "List team members for peer discovery"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.Teams

  schema do
    field :team_id, :integer, description: "Team ID"
    field :team_name, :string, description: "Team name (alternative to team_id)"
  end

  @impl true
  def execute(params, frame) do
    team =
      cond do
        params[:team_id] -> Teams.get_team(params[:team_id])
        params[:team_name] -> Teams.get_team_by_name(params[:team_name])
        true -> nil
      end

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

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
