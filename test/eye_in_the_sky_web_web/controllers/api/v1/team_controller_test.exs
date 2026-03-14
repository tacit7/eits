defmodule EyeInTheSkyWebWeb.Api.V1.TeamControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  alias EyeInTheSkyWeb.{Agents, Sessions, Teams}

  defp uniq, do: System.unique_integer([:positive])

  defp create_agent do
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Test agent #{uniq()}",
        source: "test"
      })

    agent
  end

  defp create_session(agent) do
    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Test session #{uniq()}",
        status: "working",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    session
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

      assert resp["error"] == "Failed to create team"
    end

    test "returns 422 for duplicate name", %{conn: conn} do
      team = create_team()

      conn = post(conn, ~p"/api/v1/teams", %{"name" => team.name})
      resp = json_response(conn, 422)

      assert resp["error"] == "Failed to create team"
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

      updated = Teams.get_team(team.id)
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

      assert json_response(conn, 422)["error"] == "Failed to join team"
    end

    test "returns 422 when name is missing", %{conn: conn} do
      team = create_team()
      conn = post(conn, ~p"/api/v1/teams/#{team.id}/members", %{})
      assert json_response(conn, 422)["error"] == "Failed to join team"
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
end
