defmodule EyeInTheSkyWeb.MCP.Tools.TeamStatus do
  @moduledoc "Snapshot of team members and their task statuses"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.{Repo, Teams}
  import Ecto.Query

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
                last_activity_at: m.last_activity_at
              }
            end)

          tasks = list_team_tasks(team.id)

          %{
            success: true,
            team_id: team.id,
            team_name: team.name,
            team_status: team.status,
            members: members,
            tasks: tasks,
            summary: %{
              total_members: length(members),
              active: Enum.count(members, &(&1.status == "active")),
              idle: Enum.count(members, &(&1.status == "idle")),
              done: Enum.count(members, &(&1.status == "done")),
              total_tasks: length(tasks),
              completed_tasks: Enum.count(tasks, &(&1.state_id == 3))
            }
          }
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  defp list_team_tasks(team_id) do
    from(t in EyeInTheSkyWeb.Tasks.Task,
      where: t.team_id == ^team_id,
      order_by: [asc: t.id]
    )
    |> Repo.all()
    |> Enum.map(fn t ->
      %{
        id: t.id,
        title: t.title,
        state_id: t.state_id,
        priority: t.priority
      }
    end)
  end
end
