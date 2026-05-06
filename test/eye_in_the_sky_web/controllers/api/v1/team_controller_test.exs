defmodule EyeInTheSkyWeb.Api.V1.MockSucceedingAgentManagerForTeam do
  @moduledoc "Test double — always succeeds send_message."
  def send_message(_session_id, _message, _opts \\ []), do: :ok
end

defmodule EyeInTheSkyWeb.Api.V1.TeamControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.Teams

  import EyeInTheSky.Factory

  defp api_conn do
    token = "test_api_key_#{System.unique_integer([:positive])}"
    {:ok, _} = ApiKey.create(token, "test")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  setup do
    {:ok, conn: api_conn()}
  end

  defp create_team(overrides \\ %{}) do
    {:ok, team} =
      Teams.create_team(
        Map.merge(%{name: "test-team-#{uniq()}", description: "A test team"}, overrides)
      )

    team
  end

  defp join_team(team, overrides \\ %{}) do
    {:ok, member} =
      Teams.join_team(
        Map.merge(
          %{team_id: team.id, name: "member-#{uniq()}", role: "member"},
          overrides
        )
      )

    member
  end

  # ── GET /api/v1/teams ─────────────────────────────────────────────────────

  describe "GET /api/v1/teams" do
    test "returns list of active teams", %{conn: conn} do
      create_team()
      conn = get(conn, ~p"/api/v1/teams")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert is_list(resp["teams"])
    end

    test "negative limit returns 200 and treats as no limit", %{conn: conn} do
      create_team()
      conn = get(conn, ~p"/api/v1/teams?limit=-5")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert is_list(resp["teams"])
    end

    test "status=all includes archived teams", %{conn: conn} do
      team = create_team()
      Teams.delete_team(team)

      conn = get(conn, ~p"/api/v1/teams?status=all")
      resp = json_response(conn, 200)

      ids = Enum.map(resp["teams"], & &1["id"])
      assert team.id in ids
    end

    test "excludes archived teams by default", %{conn: conn} do
      team = create_team()
      Teams.delete_team(team)

      conn = get(conn, ~p"/api/v1/teams")
      resp = json_response(conn, 200)

      ids = Enum.map(resp["teams"], & &1["id"])
      refute team.id in ids
    end

    test "filters by status=archived", %{conn: conn} do
      team = create_team()
      Teams.delete_team(team)

      conn = get(conn, ~p"/api/v1/teams?status=archived")
      resp = json_response(conn, 200)

      ids = Enum.map(resp["teams"], & &1["id"])
      assert team.id in ids
    end

    test "response includes member_count", %{conn: conn} do
      team = create_team()
      join_team(team)
      join_team(team)

      conn = get(conn, ~p"/api/v1/teams")
      resp = json_response(conn, 200)

      found = Enum.find(resp["teams"], &(&1["id"] == team.id))
      assert found["member_count"] == 2
    end
  end

  # ── GET /api/v1/teams/:id ─────────────────────────────────────────────────

  describe "GET /api/v1/teams/:id" do
    test "returns team by integer id with members", %{conn: conn} do
      team = create_team()
      join_team(team, %{name: "alpha"})

      conn = get(conn, ~p"/api/v1/teams/#{team.id}")
      resp = json_response(conn, 200)

      assert resp["id"] == team.id
      assert resp["name"] == team.name
      assert is_list(resp["members"])
      assert Enum.any?(resp["members"], &(&1["name"] == "alpha"))
    end

    test "resolves team by name", %{conn: conn} do
      team = create_team(%{name: "uniquename-#{uniq()}"})

      conn = get(conn, ~p"/api/v1/teams/#{team.name}")
      resp = json_response(conn, 200)

      assert resp["id"] == team.id
    end

    test "returns 404 for missing team", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/teams/9999999")
      assert json_response(conn, 404)["error"] == "Team not found"
    end
  end

  # ── POST /api/v1/teams ────────────────────────────────────────────────────

  describe "POST /api/v1/teams" do
    test "creates a team with name", %{conn: conn} do
      name = "my-team-#{uniq()}"

      conn = post(conn, ~p"/api/v1/teams", %{"name" => name, "description" => "A new team"})
      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert resp["name"] == name
      assert is_integer(resp["id"])
      assert is_binary(resp["uuid"])
    end

    test "returns 422 when name is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/teams", %{"description" => "no name"})
      resp = json_response(conn, 422)

      assert resp["error"] == "Validation failed"
    end

    test "returns 422 for duplicate name", %{conn: conn} do
      team = create_team()

      conn = post(conn, ~p"/api/v1/teams", %{"name" => team.name})
      resp = json_response(conn, 422)

      assert resp["error"] == "Validation failed"
    end
  end

  # ── DELETE /api/v1/teams/:id ──────────────────────────────────────────────

  describe "DELETE /api/v1/teams/:id" do
    test "archives the team", %{conn: conn} do
      team = create_team()
      conn = delete(conn, ~p"/api/v1/teams/#{team.id}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["id"] == team.id

      {:ok, updated} = Teams.get_team(team.id)
      assert updated.status == "archived"
    end

    test "returns 404 for missing team", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/teams/9999999")
      assert json_response(conn, 404)["error"] == "Team not found"
    end
  end

  # ── GET /api/v1/teams/:team_id/members ───────────────────────────────────

  describe "GET /api/v1/teams/:team_id/members" do
    test "returns members for a team", %{conn: conn} do
      team = create_team()
      join_team(team, %{name: "beta"})

      conn = get(conn, ~p"/api/v1/teams/#{team.id}/members")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["team_id"] == team.id
      assert Enum.any?(resp["members"], &(&1["name"] == "beta"))
    end

    test "returns empty list when team has no members", %{conn: conn} do
      team = create_team()
      conn = get(conn, ~p"/api/v1/teams/#{team.id}/members")
      resp = json_response(conn, 200)

      assert resp["members"] == []
    end

    test "returns 404 for missing team", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/teams/9999999/members")
      assert json_response(conn, 404)["error"] == "Team not found"
    end
  end

  # ── POST /api/v1/teams/:team_id/members ──────────────────────────────────

  describe "POST /api/v1/teams/:team_id/members (join)" do
    test "joins a team", %{conn: conn} do
      team = create_team()

      conn =
        post(conn, ~p"/api/v1/teams/#{team.id}/members", %{
          "name" => "gamma",
          "role" => "lead"
        })

      resp = json_response(conn, 201)

      assert resp["success"] == true
      assert resp["team_id"] == team.id
      assert is_integer(resp["member_id"])
    end

    test "accepts session_id for linking", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      team = create_team()

      conn =
        post(conn, ~p"/api/v1/teams/#{team.id}/members", %{
          "name" => "delta",
          "session_id" => to_string(session.id)
        })

      resp = json_response(conn, 201)
      assert resp["success"] == true
    end

    test "returns 422 for duplicate member name in same team", %{conn: conn} do
      team = create_team()
      join_team(team, %{name: "epsilon"})

      conn =
        post(conn, ~p"/api/v1/teams/#{team.id}/members", %{"name" => "epsilon"})

      assert json_response(conn, 422)["error"] == "Validation failed"
    end

    test "returns 422 when name is missing", %{conn: conn} do
      team = create_team()
      conn = post(conn, ~p"/api/v1/teams/#{team.id}/members", %{})
      assert json_response(conn, 422)["error"] == "Validation failed"
    end

    test "returns 404 for missing team", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/teams/9999999/members", %{"name" => "zeta"})
      assert json_response(conn, 404)["error"] == "Team not found"
    end
  end

  # ── PATCH /api/v1/teams/:team_id/members/:member_id ──────────────────────

  describe "PATCH /api/v1/teams/:team_id/members/:member_id (update_member)" do
    test "updates member status", %{conn: conn} do
      team = create_team()
      member = join_team(team, %{name: "eta"})

      conn =
        patch(conn, ~p"/api/v1/teams/#{team.id}/members/#{member.id}", %{
          "status" => "done"
        })

      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["status"] == "done"
      assert resp["member_id"] == member.id
    end

    test "returns 404 for missing team", %{conn: conn} do
      conn = patch(conn, ~p"/api/v1/teams/9999999/members/1", %{"status" => "done"})
      assert json_response(conn, 404)["error"] == "Team not found"
    end

    test "returns 404 for missing member", %{conn: conn} do
      team = create_team()
      conn = patch(conn, ~p"/api/v1/teams/#{team.id}/members/9999999", %{"status" => "done"})
      assert json_response(conn, 404)["error"] == "Member not found"
    end
  end

  # ── DELETE /api/v1/teams/:team_id/members/:member_id ─────────────────────

  describe "DELETE /api/v1/teams/:team_id/members/:member_id (leave)" do
    test "removes the member", %{conn: conn} do
      team = create_team()
      member = join_team(team, %{name: "theta"})

      conn = delete(conn, ~p"/api/v1/teams/#{team.id}/members/#{member.id}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["member_id"] == member.id

      assert Teams.list_members(team.id) == []
    end

    test "returns 404 for missing team", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/teams/9999999/members/1")
      assert json_response(conn, 404)["error"] == "Team not found"
    end

    test "returns 404 for missing member", %{conn: conn} do
      team = create_team()
      conn = delete(conn, ~p"/api/v1/teams/#{team.id}/members/9999999")
      assert json_response(conn, 404)["error"] == "Member not found"
    end
  end

  # ── POST /api/v1/teams/:team_id/broadcast ────────────────────────────────

  describe "POST /api/v1/teams/:team_id/broadcast" do
    test "returns 400 when body is missing", %{conn: conn} do
      team = create_team()
      agent = create_agent()
      session = create_session(agent)
      join_team(team, %{name: "sender", session_id: session.id})

      conn =
        post(conn, ~p"/api/v1/teams/#{team.id}/broadcast", %{
          "from_session_id" => session.uuid
        })

      assert json_response(conn, 400)["error"] =~ "body is required"
    end

    test "returns 400 when from_session_id is missing", %{conn: conn} do
      team = create_team()

      conn =
        post(conn, ~p"/api/v1/teams/#{team.id}/broadcast", %{
          "body" => "hello"
        })

      assert json_response(conn, 400)["error"] =~ "from_session_id is required"
    end

    test "returns 404 for unknown team", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      conn =
        post(conn, ~p"/api/v1/teams/9999999/broadcast", %{
          "from_session_id" => session.uuid,
          "body" => "hello"
        })

      assert json_response(conn, 404)["error"] =~ "Team not found"
    end

    test "returns 404 for unknown sender session", %{conn: conn} do
      team = create_team()

      conn =
        post(conn, ~p"/api/v1/teams/#{team.id}/broadcast", %{
          "from_session_id" => Ecto.UUID.generate(),
          "body" => "hello"
        })

      assert json_response(conn, 404)["error"] =~ "Sender session not found"
    end

    test "returns 403 when sender is not a team member", %{conn: conn} do
      team = create_team()
      agent = create_agent()
      session = create_session(agent)

      conn =
        post(conn, ~p"/api/v1/teams/#{team.id}/broadcast", %{
          "from_session_id" => session.uuid,
          "body" => "hello"
        })

      assert json_response(conn, 403)["error"] =~ "not a member"
    end

    test "returns sent_count=0 when no other active members exist", %{conn: conn} do
      team = create_team()
      agent = create_agent()
      session = create_session(agent)
      join_team(team, %{name: "only-member", session_id: session.id})

      conn =
        post(conn, ~p"/api/v1/teams/#{team.id}/broadcast", %{
          "from_session_id" => session.uuid,
          "body" => "hello"
        })

      resp = json_response(conn, 200)
      assert resp["success"] == true
      assert resp["sent_count"] == 0
    end

    test "rejects broadcast from terminated sender session", %{conn: conn} do
      team = create_team()
      agent = create_agent()
      dead_session = create_session(agent, %{status: "completed"})
      join_team(team, %{name: "dead-sender", session_id: dead_session.id})

      conn =
        post(conn, ~p"/api/v1/teams/#{team.id}/broadcast", %{
          "from_session_id" => dead_session.uuid,
          "body" => "ghost broadcast"
        })

      assert json_response(conn, 422)["error"] =~ "terminated"
    end

    test "skips completed and failed sessions", %{conn: conn} do
      team = create_team()

      sender_agent = create_agent()
      sender = create_session(sender_agent)
      join_team(team, %{name: "sender", session_id: sender.id})

      done_agent = create_agent()
      done_session = create_session(done_agent, %{status: "completed"})
      join_team(team, %{name: "done-member", session_id: done_session.id})

      failed_agent = create_agent()
      failed_session = create_session(failed_agent, %{status: "failed"})
      join_team(team, %{name: "failed-member", session_id: failed_session.id})

      conn =
        post(conn, ~p"/api/v1/teams/#{team.id}/broadcast", %{
          "from_session_id" => sender.uuid,
          "body" => "test broadcast"
        })

      resp = json_response(conn, 200)
      assert resp["success"] == true
      # Both targets are terminated — nothing should be sent
      assert resp["sent_count"] == 0
    end

    test "delivers to active members and returns correct sent_count", %{conn: conn} do
      Application.put_env(
        :eye_in_the_sky,
        :agent_manager_module,
        EyeInTheSkyWeb.Api.V1.MockSucceedingAgentManagerForTeam
      )

      on_exit(fn ->
        Application.put_env(
          :eye_in_the_sky,
          :agent_manager_module,
          EyeInTheSky.Agents.MockAgentManager
        )
      end)

      team = create_team()

      sender_agent = create_agent()
      sender = create_session(sender_agent)
      join_team(team, %{name: "sender", session_id: sender.id})

      r1_agent = create_agent()
      r1 = create_session(r1_agent)
      join_team(team, %{name: "recv-1", session_id: r1.id})

      r2_agent = create_agent()
      r2 = create_session(r2_agent)
      join_team(team, %{name: "recv-2", session_id: r2.id})

      conn =
        post(conn, ~p"/api/v1/teams/#{team.id}/broadcast", %{
          "from_session_id" => sender.uuid,
          "body" => "ping"
        })

      resp = json_response(conn, 200)
      assert resp["success"] == true
      assert resp["sent_count"] == 2
      assert resp["failed"] == 0
    end
  end

  # ── PATCH /api/v1/teams/:id ───────────────────────────────────────────────

  describe "PATCH /api/v1/teams/:id" do
    test "updates team name", %{conn: conn} do
      team = create_team(%{name: "old-name"})
      conn = patch(conn, ~p"/api/v1/teams/#{team.id}", %{"name" => "new-name"})
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["name"] == "new-name"
      assert resp["id"] == team.id
    end

    test "updates team description", %{conn: conn} do
      team = create_team()
      conn = patch(conn, ~p"/api/v1/teams/#{team.id}", %{"description" => "updated desc"})
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["description"] == "updated desc"
    end

    test "updates name and description together", %{conn: conn} do
      team = create_team(%{name: "before", description: "old"})

      conn =
        patch(conn, ~p"/api/v1/teams/#{team.id}", %{
          "name" => "after",
          "description" => "new"
        })

      resp = json_response(conn, 200)
      assert resp["name"] == "after"
      assert resp["description"] == "new"
    end

    test "returns 404 for unknown team", %{conn: conn} do
      conn = patch(conn, ~p"/api/v1/teams/999999", %{"name" => "whatever"})
      assert json_response(conn, 404)
    end

    test "persists change to database", %{conn: conn} do
      team = create_team(%{name: "persist-me"})
      patch(conn, ~p"/api/v1/teams/#{team.id}", %{"name" => "persisted"})
      {:ok, reloaded} = Teams.get_team(team.id)
      assert reloaded.name == "persisted"
    end

    test "returns 422 for empty name string", %{conn: conn} do
      team = create_team()
      conn = patch(conn, ~p"/api/v1/teams/#{team.id}", %{"name" => ""})
      assert conn.status in [422, 400]
    end

    test "returns 400 when no updateable fields given", %{conn: conn} do
      team = create_team()
      conn = patch(conn, ~p"/api/v1/teams/#{team.id}", %{})
      assert json_response(conn, 400)
    end

    test "ignores injected fields like status and uuid", %{conn: conn} do
      team = create_team(%{name: "safe-name"})

      conn =
        patch(conn, ~p"/api/v1/teams/#{team.id}", %{
          "name" => "ok-name",
          "status" => "archived",
          "uuid" => "00000000-0000-0000-0000-000000000000"
        })

      resp = json_response(conn, 200)
      assert resp["name"] == "ok-name"
      assert resp["status"] != "archived"
      assert resp["uuid"] != "00000000-0000-0000-0000-000000000000"
    end
  end
end
