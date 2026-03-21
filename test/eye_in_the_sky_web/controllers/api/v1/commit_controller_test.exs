defmodule EyeInTheSkyWeb.Api.V1.CommitControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.{Agents, Commits, Sessions}

  import EyeInTheSky.Factory

  defp create_commit(session, overrides \\ %{}) do
    {:ok, commit} =
      Commits.create_commit(
        Map.merge(
          %{
            session_id: session.id,
            commit_hash: "abc#{uniq()}",
            commit_message: "Test commit #{uniq()}"
          },
          overrides
        )
      )

    commit
  end

  # ---- GET /api/v1/commits ----

  describe "GET /api/v1/commits" do
    test "returns commit list", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      create_commit(session)
      conn = get(conn, ~p"/api/v1/commits")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert is_list(resp["commits"])
    end

    test "filters by session_id", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      commit = create_commit(session)

      conn = get(conn, ~p"/api/v1/commits?session_id=#{session.uuid}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert Enum.any?(resp["commits"], &(&1["id"] == commit.id))
    end

    test "filters by agent_id (session uuid)", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      commit = create_commit(session)

      conn = get(conn, ~p"/api/v1/commits?agent_id=#{session.uuid}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert Enum.any?(resp["commits"], &(&1["id"] == commit.id))
    end

    test "returns empty list for unknown session_id", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/commits?session_id=#{Ecto.UUID.generate()}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["commits"] == []
    end

    test "each commit has expected fields", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      commit = create_commit(session, %{commit_hash: "deadbeef", commit_message: "fix bug"})

      conn = get(conn, ~p"/api/v1/commits?session_id=#{session.uuid}")
      resp = json_response(conn, 200)

      found = Enum.find(resp["commits"], &(&1["id"] == commit.id))
      assert found["commit_hash"] == "deadbeef"
      assert found["commit_message"] == "fix bug"
    end
  end

  # ---- POST /api/v1/commits ----

  describe "POST /api/v1/commits" do
    test "creates commits for a session", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      conn =
        post(conn, ~p"/api/v1/commits", %{
          "agent_id" => session.uuid,
          "commit_hashes" => ["abc123", "def456"],
          "commit_messages" => ["First commit", "Second commit"]
        })

      resp = json_response(conn, 201)

      assert length(resp["commits"]) == 2
      assert Enum.any?(resp["commits"], &(&1["commit_hash"] == "abc123"))
      assert Enum.any?(resp["commits"], &(&1["commit_hash"] == "def456"))
    end

    test "creates commits without messages", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      conn =
        post(conn, ~p"/api/v1/commits", %{
          "agent_id" => session.uuid,
          "commit_hashes" => ["abc999"]
        })

      resp = json_response(conn, 201)
      assert length(resp["commits"]) == 1
    end

    test "returns 400 when agent_id is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/commits", %{"commit_hashes" => ["abc"]})
      assert json_response(conn, 400)["error"] == "agent_id is required"
    end

    test "returns 400 when commit_hashes is empty", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/commits", %{"agent_id" => Ecto.UUID.generate()})
      assert json_response(conn, 400)["error"] == "commit_hashes is required"
    end

    test "returns 404 when agent session not found", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/commits", %{
          "agent_id" => Ecto.UUID.generate(),
          "commit_hashes" => ["abc"]
        })

      assert json_response(conn, 404)["error"] == "Agent not found"
    end
  end
end
