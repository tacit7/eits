defmodule EyeInTheSkyWeb.MCP.Tools.TeamCreate do
  @moduledoc "Create a new agent team"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.Teams

  schema do
    field :name, :string, required: true, description: "Team name (unique)"
    field :description, :string, description: "Team purpose/description"

    field :project_id, :integer,
      description: "Project ID to associate. Auto-resolved from session if omitted."
  end

  @impl true
  def execute(params, frame) do
    project_id = params[:project_id] || frame.assigns[:eits_project_id]

    attrs = %{
      name: params[:name],
      description: params[:description],
      project_id: project_id
    }

    result =
      case Teams.create_team(attrs) do
        {:ok, team} ->
          %{
            success: true,
            message: "Team created",
            team_id: team.id,
            team_uuid: team.uuid,
            name: team.name
          }

        {:error, changeset} ->
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          %{success: false, message: "Failed to create team", errors: errors}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
