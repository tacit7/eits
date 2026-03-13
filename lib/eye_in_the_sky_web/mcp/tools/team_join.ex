defmodule EyeInTheSkyWeb.MCP.Tools.TeamJoin do
  @moduledoc "Register an agent as a member of a team"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.{Sessions, Teams}

  schema do
    field :team_id, :integer, description: "Team ID to join"
    field :team_name, :string, description: "Team name to join (alternative to team_id)"

    field :name, :string,
      required: true,
      description: "Member alias within the team (e.g. 'researcher', 'implementer')"

    field :role, :string, description: "Role: lead, member (default: member)"
    field :agent_id, :integer, description: "Agent ID. Auto-resolved from session if omitted."
    field :session_id, :string, description: "Session UUID. Auto-resolved from frame if omitted."
  end

  @impl true
  def execute(params, frame) do
    team =
      cond do
        params[:team_id] -> Teams.get_team(params[:team_id])
        params[:team_name] -> Teams.get_team_by_name(params[:team_name])
        true -> nil
      end

    with {:ok, team} <- resolve_team(team),
         {:ok, session_db_id, agent_db_id} <- resolve_ids(params, frame) do
      attrs = %{
        team_id: team.id,
        name: params[:name],
        role: params[:role] || "member",
        agent_id: agent_db_id,
        session_id: session_db_id
      }

      result =
        case Teams.join_team(attrs) do
          {:ok, member} ->
            %{
              success: true,
              message: "Joined team #{team.name} as #{member.name}",
              member_id: member.id,
              team_id: team.id,
              team_name: team.name
            }

          {:error, changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
            %{success: false, message: "Failed to join team", errors: errors}
        end

      response = Response.tool() |> Response.json(result)
      {:reply, response, frame}
    else
      {:error, msg} ->
        response = Response.tool() |> Response.json(%{success: false, message: msg})
        {:reply, response, frame}
    end
  end

  defp resolve_team(nil), do: {:error, "Team not found"}
  defp resolve_team(team), do: {:ok, team}

  defp resolve_ids(params, frame) do
    session_uuid = params[:session_id] || frame.assigns[:eits_session_id]

    {session_db_id, agent_db_id} =
      if session_uuid do
        case Sessions.get_session_by_uuid(session_uuid) do
          {:ok, session} -> {session.id, session.agent_id}
          _ -> {nil, nil}
        end
      else
        {nil, nil}
      end

    agent_db_id = params[:agent_id] || agent_db_id
    {:ok, session_db_id, agent_db_id}
  end
end
