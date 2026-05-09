defmodule EyeInTheSkyWeb.Api.V1.TeamController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, Sessions, Teams}
  alias EyeInTheSky.Messaging.DMDelivery
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  # GET /api/v1/teams
  def index(conn, params) do
    with {:ok, scope} <- get_project_scope(conn, params) do
      limit =
        case parse_int(params["limit"]) do
          n when is_integer(n) and n > 0 -> n
          _ -> nil
        end

      # Use explicit project_id if provided, otherwise fall back to session's project (if any)
      project_id = params["project_id"] && parse_int(params["project_id"])

      project_id =
        project_id ||
          case scope do
            :bearer_only -> nil
            session -> session.project_id
          end

      opts =
        []
        |> maybe_opt(:project_id, project_id)
        |> maybe_opt(:status, params["status"])
        |> maybe_opt(:member_agent_uuid, params["member_agent_uuid"])
        |> maybe_opt(:limit, limit)

      teams = Teams.list_teams(opts)

      json(conn, %{
        success: true,
        teams: Enum.map(teams, &ApiPresenter.present_team/1)
      })
    else
      {:error, :unauthorized} ->
        {:error, :unauthorized, "Unauthorized"}
    end
  end

  # GET /api/v1/teams/:id
  def show(conn, %{"id" => id} = params) do
    with {:ok, scope} <- get_project_scope(conn, params),
         {:ok, team} <- resolve_team(id),
         :ok <- validate_project_access(team, scope) do
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
    else
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}
      {:error, :unauthorized} ->
        {:error, :unauthorized, "Unauthorized"}
      {:error, :forbidden} ->
        {:error, :forbidden, "Access denied: team does not belong to your project"}
    end
  end

  # POST /api/v1/teams
  def create(conn, params) do
    with {:ok, scope} <- get_project_scope(conn, params),
         {:ok, project_id} <- resolve_create_project_id(params, scope) do
      attrs = %{
        name: params["name"],
        description: params["description"],
        project_id: project_id
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
    else
      {:error, :unauthorized} ->
        {:error, :unauthorized, "Unauthorized"}
      {:error, :forbidden} ->
        {:error, :forbidden, "Access denied: cannot create team in this project"}
    end
  end

  # PATCH /api/v1/teams/:id
  def update(conn, %{"id" => id} = params) do
    attrs =
      params
      |> Map.take(["name", "description"])
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    if map_size(attrs) == 0 do
      {:error, :bad_request, "at least one of name or description is required"}
    else
      with {:ok, scope} <- get_project_scope(conn, params),
           {:ok, team} <- resolve_team(id),
           :ok <- validate_project_access(team, scope) do
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
      else
        {:error, :not_found} ->
          {:error, :not_found, "Team not found"}
        {:error, :unauthorized} ->
          {:error, :unauthorized, "Unauthorized"}
        {:error, :forbidden} ->
          {:error, :forbidden, "Access denied: team does not belong to your project"}
      end
    end
  end

  # DELETE /api/v1/teams/:id
  def delete(conn, %{"id" => id} = params) do
    with {:ok, scope} <- get_project_scope(conn, params),
         {:ok, team} <- resolve_team(id),
         :ok <- validate_project_access(team, scope) do
      case Teams.delete_team(team) do
        {:ok, _} ->
          json(conn, %{success: true, message: "Team archived", id: team.id})

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}
      {:error, :unauthorized} ->
        {:error, :unauthorized, "Unauthorized"}
      {:error, :forbidden} ->
        {:error, :forbidden, "Access denied: team does not belong to your project"}
    end
  end

  # GET /api/v1/teams/:team_id/members
  def list_members(conn, %{"team_id" => id} = params) do
    with {:ok, scope} <- get_project_scope(conn, params),
         {:ok, team} <- resolve_team(id),
         :ok <- validate_project_access(team, scope) do
      members = Teams.list_members(team.id)

      json(conn, %{
        success: true,
        team_id: team.id,
        members: Enum.map(members, &ApiPresenter.present_member/1)
      })
    else
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}
      {:error, :unauthorized} ->
        {:error, :unauthorized, "Unauthorized"}
      {:error, :forbidden} ->
        {:error, :forbidden, "Access denied: team does not belong to your project"}
    end
  end

  # POST /api/v1/teams/:team_id/members
  def join(conn, %{"team_id" => id} = params) do
    with {:ok, scope} <- get_project_scope(conn, params),
         {:ok, team} <- resolve_team(id),
         :ok <- validate_project_access(team, scope) do
      attrs = %{
        team_id: team.id,
        name: params["name"],
        role: params["role"] || "member",
        agent_id: resolve_id(params["agent_id"], &Agents.get_agent_by_uuid/1),
        session_id:
          resolve_id(params["session_id"], &Sessions.get_session_by_uuid/1)
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
    else
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}
      {:error, :unauthorized} ->
        {:error, :unauthorized, "Unauthorized"}
      {:error, :forbidden} ->
        {:error, :forbidden, "Access denied: team does not belong to your project"}
    end
  end

  # PATCH /api/v1/teams/:team_id/members/:member_id
  def update_member(conn, %{"team_id" => team_id, "member_id" => member_id} = params) do
    with {:ok, scope} <- get_project_scope(conn, params),
         {:ok, team} <- resolve_team(team_id),
         :ok <- validate_project_access(team, scope) do
      case Teams.get_member(member_id) do
        {:ok, member} -> do_update_member(conn, member, params)
        {:error, :not_found} -> {:error, :not_found, "Member not found"}
      end
    else
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}
      {:error, :unauthorized} ->
        {:error, :unauthorized, "Unauthorized"}
      {:error, :forbidden} ->
        {:error, :forbidden, "Access denied: team does not belong to your project"}
    end
  end

  # DELETE /api/v1/teams/:team_id/members/:member_id
  def leave(conn, %{"team_id" => team_id, "member_id" => member_id} = params) do
    with {:ok, scope} <- get_project_scope(conn, params),
         {:ok, team} <- resolve_team(team_id),
         :ok <- validate_project_access(team, scope) do
      case Teams.get_member(member_id) do
        {:ok, member} -> do_leave_team(conn, member)
        {:error, :not_found} -> {:error, :not_found, "Member not found"}
      end
    else
      {:error, :not_found} ->
        {:error, :not_found, "Team not found"}
      {:error, :unauthorized} ->
        {:error, :unauthorized, "Unauthorized"}
      {:error, :forbidden} ->
        {:error, :forbidden, "Access denied: team does not belong to your project"}
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
        with {:ok, scope} <- get_project_scope(conn, params),
             {:ok, team} <- resolve_team(id),
             :ok <- validate_project_access(team, scope) do
          do_broadcast(conn, team, from_raw, String.trim(body))
        else
          {:error, :not_found} ->
            {:error, :not_found, "Team not found"}
          {:error, :unauthorized} ->
            {:error, :unauthorized, "Unauthorized"}
          {:error, :forbidden} ->
            {:error, :forbidden, "Access denied: team does not belong to your project"}
        end
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────────

  # Returns {:ok, session} when a session/agent identifier is provided, or
  # {:ok, :bearer_only} when the caller authenticated only with a Bearer API key.
  # The caller is already authenticated by the plug pipeline; this is purely about
  # resolving optional project-scope context for ownership checks.
  defp get_project_scope(conn, params) do
    session_id_raw = params["session_id"]
    agent_id_raw = params["agent_id"]
    header_session = conn |> Plug.Conn.get_req_header("x-eits-session") |> List.first()

    cond do
      session_id_raw && session_id_raw != "" ->
        resolve_session(session_id_raw)

      agent_id_raw && agent_id_raw != "" ->
        resolve_agent_session(agent_id_raw)

      header_session && header_session != "" ->
        resolve_session(header_session)

      true ->
        {:ok, :bearer_only}
    end
  end

  defp resolve_session(raw) do
    if int_id = parse_int(raw) do
      Sessions.get_session(int_id)
    else
      Sessions.get_session_by_uuid(raw)
    end
  end

  defp resolve_agent_session(raw) do
    with {:ok, agent} <- resolve_agent(raw) do
      sessions = Sessions.list_sessions_for_agent(agent.id)

      case Enum.at(sessions, 0) do
        nil -> {:error, :unauthorized}
        session -> {:ok, session}
      end
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp resolve_agent(raw) do
    if int_id = parse_int(raw) do
      Agents.get_agent(int_id)
    else
      Agents.get_agent_by_uuid(raw)
    end
  end

  # Bearer-only callers have no project context — skip ownership check.
  defp validate_project_access(_team, :bearer_only), do: :ok

  defp validate_project_access(team, session) do
    if is_nil(team.project_id) or is_nil(session.project_id) or
         team.project_id == session.project_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  # Bearer-only: use explicit project_id param (may be nil — that's fine for unrestricted teams)
  defp resolve_create_project_id(params, :bearer_only) do
    {:ok, params["project_id"] && parse_int(params["project_id"])}
  end

  defp resolve_create_project_id(params, session) do
    case parse_int(params["project_id"]) do
      nil ->
        # No project_id provided, use requester's project
        {:ok, session.project_id}

      project_id ->
        # Project_id provided, validate it matches requester's project
        if is_nil(session.project_id) or project_id == session.project_id do
          {:ok, project_id}
        else
          {:error, :forbidden}
        end
    end
  end

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
         :ok <- check_sender_not_terminated(from_session),
         :ok <- check_is_team_member(members, from_session) do
      targets =
        Enum.filter(members, fn m ->
          not is_nil(m.session_id) and
            m.session_id != from_session.id and
            not is_nil(m.session) and
            m.session.status not in Sessions.terminated_statuses()
        end)

      sender_name = from_session.name || "agent"

      dm_body =
        "Broadcast from #{sender_name} (session:#{from_session.uuid}) [team:#{team.name}] #{body}"

      results =
        Enum.map(targets, fn m ->
          case DMDelivery.deliver_and_persist(m.session_id, from_session.id, dm_body, %{
                 from_session_uuid: from_session.uuid,
                 to_session_id: m.session_id,
                 broadcast: true
               }) do
            {:ok, _} -> :ok
            {:error, _} = err -> err
          end
        end)

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
      {:error, :not_found} ->
        {:error, :not_found, "Sender session not found"}

      {:error, :sender_terminated} ->
        {:error, :unprocessable_entity,
         "Sender session is terminated and cannot broadcast"}

      {:error, :not_member} ->
        {:error, :forbidden, "Sender is not a member of this team"}
    end
  end

  defp check_sender_not_terminated(session) do
    if session.status in Sessions.terminated_statuses(),
      do: {:error, :sender_terminated},
      else: :ok
  end

  defp check_is_team_member(members, session) do
    if Enum.any?(members, &(&1.session_id == session.id)),
      do: :ok,
      else: {:error, :not_member}
  end

  defp resolve_broadcast_sender(raw) do
    if int_id = parse_int(raw) do
      Sessions.get_session(int_id)
    else
      Sessions.get_session_by_uuid(raw)
    end
  end
end
