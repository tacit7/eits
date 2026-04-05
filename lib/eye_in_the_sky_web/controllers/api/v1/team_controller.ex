defmodule EyeInTheSkyWeb.Api.V1.TeamController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.Teams
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  # GET /api/v1/teams
  def index(conn, params) do
    opts =
      []
      |> maybe_opt(:project_id, params["project_id"])
      |> maybe_opt(:status, params["status"])

    teams = Teams.list_teams(opts)

    json(conn, %{
      success: true,
      teams: Enum.map(teams, &ApiPresenter.present_team/1)
    })
  end

  # GET /api/v1/teams/:id
  def show(conn, %{"id" => id}) do
    case resolve_team(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Team not found"})

      team ->
        members = Teams.list_members(team.id)

        json(conn, %{
          id: team.id,
          uuid: team.uuid,
          name: team.name,
          description: team.description,
          status: team.status,
          project_id: team.project_id,
          created_at: to_string(team.created_at),
          archived_at: team.archived_at && to_string(team.archived_at),
          members: Enum.map(members, &ApiPresenter.present_member/1)
        })
    end
  end

  # POST /api/v1/teams
  def create(conn, params) do
    attrs = %{
      name: params["name"],
      description: params["description"],
      project_id: params["project_id"]
    }

    case Teams.create_team(attrs) do
      {:ok, team} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          message: "Team created",
          id: team.id,
          uuid: team.uuid,
          name: team.name
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create team", details: translate_errors(changeset)})
    end
  end

  # DELETE /api/v1/teams/:id
  def delete(conn, %{"id" => id}) do
    case resolve_team(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Team not found"})

      team ->
        case Teams.delete_team(team) do
          {:ok, _} ->
            json(conn, %{success: true, message: "Team archived", id: team.id})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed", details: translate_errors(changeset)})
        end
    end
  end

  # GET /api/v1/teams/:team_id/members
  def list_members(conn, %{"team_id" => id}) do
    case resolve_team(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Team not found"})

      team ->
        members = Teams.list_members(team.id)

        json(conn, %{
          success: true,
          team_id: team.id,
          members: Enum.map(members, &ApiPresenter.present_member/1)
        })
    end
  end

  # POST /api/v1/teams/:team_id/members
  def join(conn, %{"team_id" => id} = params) do
    case resolve_team(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Team not found"})

      team ->
        attrs = %{
          team_id: team.id,
          name: params["name"],
          role: params["role"] || "member",
          agent_id: params["agent_id"],
          session_id: resolve_id(params["session_id"], &EyeInTheSky.Sessions.get_session_by_uuid/1)
        }

        case Teams.join_team(attrs) do
          {:ok, member} ->
            conn
            |> put_status(:created)
            |> json(%{
              success: true,
              message: "Joined team #{team.name} as #{member.name}",
              member_id: member.id,
              team_id: team.id,
              team_name: team.name
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to join team", details: translate_errors(changeset)})
        end
    end
  end

  # PATCH /api/v1/teams/:team_id/members/:member_id
  def update_member(conn, %{"team_id" => team_id, "member_id" => member_id} = params) do
    case resolve_team(team_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Team not found"})

      _team ->
        case Teams.get_member(member_id) do
          nil -> conn |> put_status(:not_found) |> json(%{error: "Member not found"})
          member -> do_update_member(conn, member, params)
        end
    end
  end

  # DELETE /api/v1/teams/:team_id/members/:member_id
  def leave(conn, %{"team_id" => team_id, "member_id" => member_id}) do
    case resolve_team(team_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Team not found"})

      _team ->
        case Teams.get_member(member_id) do
          nil -> conn |> put_status(:not_found) |> json(%{error: "Member not found"})
          member -> do_leave_team(conn, member)
        end
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────────

  defp resolve_team(id) do
    if int_id = parse_int(id), do: Teams.get_team(int_id), else: Teams.get_team_by_name(id)
  end

  defp do_update_member(conn, member, params) do
    case Teams.update_member_status(member, params["status"]) do
      {:ok, updated} ->
        json(conn, %{success: true, member_id: updated.id, status: updated.status})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to update member", details: translate_errors(changeset)})
    end
  end

  defp do_leave_team(conn, member) do
    case Teams.leave_team(member) do
      {:ok, _} ->
        json(conn, %{success: true, message: "Left team", member_id: member.id})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to leave team", details: translate_errors(changeset)})
    end
  end
end
