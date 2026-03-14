defmodule EyeInTheSkyWeb.MCP.Tools.TeamDelete do
  @moduledoc "Archive/delete a team when work is complete"

  use Anubis.Server.Component, type: :tool

  alias EyeInTheSkyWeb.MCP.Tools.{Helpers, ResponseHelper}
  alias EyeInTheSkyWeb.Teams

  schema do
    field :team_id, :integer, description: "Team ID to delete"
    field :team_name, :string, description: "Team name to delete (alternative to team_id)"
  end

  @impl true
  def execute(params, frame) do
    team = Helpers.resolve_team(params)

    result =
      case team do
        nil ->
          %{success: false, message: "Team not found"}

        team ->
          case Teams.delete_team(team) do
            {:ok, _} -> %{success: true, message: "Team archived", team_id: team.id}
            {:error, cs} -> %{success: false, message: "Failed: #{inspect(cs.errors)}"}
          end
      end

    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end
end
