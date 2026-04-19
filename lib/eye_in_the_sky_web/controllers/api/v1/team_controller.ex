defmodule EyeInTheSkyWeb.Api.V1.TeamController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Messages, Sessions, Teams}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @terminated_statuses ~w(completed failed)

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
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}

      {:ok, team} ->
        members = Teams.list_members(team.id)

        json(conn, %{
          id: team.id,
          uuid: team.uuid,
          name: team.name,
          description: team.description,
          status: team.status,
          project_id: team.project_id,
          created_at: to_string(team.created_at),
          archived_at: if(team.archived_at, do: to_string(team.archived_at)),
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
        {:error, changeset}
    end
  end

  # PATCH /api/v1/teams/:id
  def update(conn, %{"id" => id} = params) do
    case resolve_team(id) do
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}

      {:ok, team} ->
        attrs =
          params
          |> Map.take(["name", "description"])
          |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

        case Teams.update_team(team, attrs) do
          {:ok, updated} ->
            json(conn, %{
              success: true,
              id: updated.id,
              uuid: updated.uuid,
              name: updated.name,
              description: updated.description,
              status: updated.status
            })

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  # DELETE /api/v1/teams/:id
  def delete(conn, %{"id" => id}) do
    case resolve_team(id) do
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}

      {:ok, team} ->
        case Teams.delete_team(team) do
          {:ok, _} ->
            json(conn, %{success: true, message: "Team archived", id: team.id})

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  # GET /api/v1/teams/:team_id/members
  def list_members(conn, %{"team_id" => id}) do
    case resolve_team(id) do
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}

      {:ok, team} ->
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
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}

      {:ok, team} ->
        attrs = %{
          team_id: team.id,
          name: params["name"],
          role: params["role"] || "member",
          agent_id: params["agent_id"],
          session_id:
            resolve_id(params["session_id"], &EyeInTheSky.Sessions.get_session_by_uuid/1)
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
            {:error, changeset}
        end
    end
  end

  # PATCH /api/v1/teams/:team_id/members/:member_id
  def update_member(conn, %{"team_id" => team_id, "member_id" => member_id} = params) do
    case resolve_team(team_id) do
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}

      {:ok, _team} ->
        case Teams.get_member(member_id) do
          {:error, :not_found} ->
            {:error, :not_found, "Member not found"}

          {:ok, member} ->
            do_update_member(conn, member, params)
        end
    end
  end

  # DELETE /api/v1/teams/:team_id/members/:member_id
  def leave(conn, %{"team_id" => team_id, "member_id" => member_id}) do
    case resolve_team(team_id) do
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}

      {:ok, _team} ->
        case Teams.get_member(member_id) do
          {:error, :not_found} ->
            {:error, :not_found, "Member not found"}

          {:ok, member} ->
            do_leave_team(conn, member)
        end
    end
  end

  # POST /api/v1/teams/:team_id/broadcast
  def broadcast(conn, %{"team_id" => id} = params) do
    body = params["body"]
    from_raw = params["from_session_id"]

    cond do
      is_nil(body) or String.trim(body) == "" ->
        {:error, :bad_request, "body is required"}

      is_nil(from_raw) or from_raw == "" ->
        {:error, :bad_request, "from_session_id is required"}

      true ->
        case resolve_team(id) do
          {:error, :not_found} ->
            {:error, :not_found, "Team not found"}

          {:ok, team} ->
            do_broadcast(conn, team, from_raw, String.trim(body))
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
        {:error, changeset}
    end
  end

  defp do_leave_team(conn, member) do
    case Teams.leave_team(member) do
      {:ok, _} ->
        json(conn, %{success: true, message: "Left team", member_id: member.id})

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp do_broadcast(conn, team, from_raw, body) do
    members = Teams.list_members(team.id)

    with {:ok, from_session} <- resolve_broadcast_sender(from_raw),
         {:from_active, false} <-
           {:from_active, from_session.status in @terminated_statuses},
         {:member, true} <-
           {:member, Enum.any?(members, &(&1.session_id == from_session.id))} do
      targets =
        Enum.filter(members, fn m ->
          not is_nil(m.session_id) and
            m.session_id != from_session.id and
            not is_nil(m.session) and
            m.session.status not in @terminated_statuses
        end)

      sender_name = from_session.name || "agent"

      dm_body =
        "Broadcast from #{sender_name} (session:#{from_session.uuid}) [team:#{team.name}] #{body}"

      results = Enum.map(targets, &deliver_broadcast_dm(&1, from_session, dm_body))

      sent = Enum.count(results, &match?(:ok, &1))
      failed = Enum.count(results, &match?({:error, _}, &1))

      json(conn, %{
        success: true,
        message: "Broadcast sent to #{sent} member(s)",
        team_id: team.id,
        sent_count: sent,
        failed: failed
      })
    else
      {:error, :not_found} -> {:error, :not_found, "Sender session not found"}
      {:from_active, true} -> {:error, :unprocessable_entity, "Sender session is terminated and cannot broadcast"}
      {:member, false} -> {:error, :forbidden, "Sender is not a member of this team"}
    end
  end

  defp resolve_broadcast_sender(raw) do
    if int_id = parse_int(raw) do
      Sessions.get_session(int_id)
    else
      Sessions.get_session_by_uuid(raw)
    end
  end

  defp deliver_broadcast_dm(member, from_session, dm_body) do
    case agent_manager_mod().send_message(member.session_id, dm_body) do
      result when result == :ok or (is_tuple(result) and elem(result, 0) == :ok) ->
        attrs = %{
          uuid: Ecto.UUID.generate(),
          session_id: member.session_id,
          from_session_id: from_session.id,
          to_session_id: member.session_id,
          body: dm_body,
          sender_role: "agent",
          recipient_role: "agent",
          direction: "inbound",
          status: "sent",
          provider: "claude",
          metadata: %{
            from_session_uuid: from_session.uuid,
            to_session_id: member.session_id,
            broadcast: true
          }
        }

        case Messages.create_message(attrs) do
          {:ok, msg} ->
            EyeInTheSky.Events.session_new_dm(member.session_id, msg)
            :ok

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp agent_manager_mod do
    Application.get_env(:eye_in_the_sky, :agent_manager_module, AgentManager)
  end
end
