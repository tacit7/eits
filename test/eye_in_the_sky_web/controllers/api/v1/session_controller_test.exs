defmodule EyeInTheSkyWeb.Api.V1.SessionControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.{Commits, Contexts, Notes, Sessions, Tasks}
  alias EyeInTheSky.Accounts.ApiKey

  import EyeInTheSky.Factory

  defp api_conn do
    token = "test_api_key_#{System.unique_integer([:positive])}"
    {:ok, _} = ApiKey.create(token, "test")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  defp create_task(overrides \\ %{}) do
    {:ok, task} =
      Tasks.create_task(
        Map.merge(
          %{uuid: Ecto.UUID.generate(), title: "Task #{uniq()}", state_id: 1},
          overrides
        )
      )

    task
  end

  defp create_note(session, overrides \\ %{}) do
    {:ok, note} =
      Notes.create_note(
        Map.merge(
          %{parent_id: to_string(session.id), parent_type: "session", body: "Note #{uniq()}"},
          overrides
        )
      )

    note
  end

  defp create_commit(session, overrides \\ %{}) do
    {:ok, commit} =
      Commits.create_commit(
        Map.merge(
          %{
            session_id: session.id,
            commit_hash: "hash#{uniq()}",
            commit_message: "Commit #{uniq()}"
          },
          overrides
        )
      )

    commit
  end

  # ---- GET /api/v1/sessions ----

  describe "GET /api/v1/sessions" do
    test "returns session list", %{conn: conn} do
      agent = create_agent()
      create_session(agent)
      conn = get(conn, ~p"/api/v1/sessions")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert is_list(resp["results"])
    end

    test "filters by status", %{conn: conn} do
      agent = create_agent()
      create_session(agent, %{status: "completed"})
      conn = get(conn, ~p"/api/v1/sessions?status=completed")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert Enum.all?(resp["results"], &(&1["status"] == "completed"))
    end

    test "respects limit param", %{conn: conn} do
      agent = create_agent()
      for _ <- 1..5, do: create_session(agent)
      conn = get(conn, ~p"/api/v1/sessions?limit=2")
      resp = json_response(conn, 200)

      assert length(resp["results"]) <= 2
    end
  end

  # ---- POST /api/v1/sessions ----

  describe "POST /api/v1/sessions" do
    test "creates agent and session", %{conn: conn} do
      uuid = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/v1/sessions", %{
          "session_id" => uuid,
          "name" => "My session",
          "description" => "Doing work"
        })

      resp = json_response(conn, 201)

      assert resp["uuid"] == uuid
      assert resp["status"] == "working"
      assert is_integer(resp["id"])
      assert is_integer(resp["agent_id"])
    end

    test "returns 400 when session_id is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/sessions", %{"name" => "no session id"})
      assert json_response(conn, 400)["error"] == "session_id is required"
    end

    test "parses model into provider/name", %{conn: conn} do
      uuid = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/v1/sessions", %{
          "session_id" => uuid,
          "name" => "Model test",
          "model" => "claude-sonnet-4-5-20250929"
        })

      assert json_response(conn, 201)["uuid"] == uuid
    end

    test "persists name on fresh session create", %{conn: conn} do
      uuid = Ecto.UUID.generate()

      post(conn, ~p"/api/v1/sessions", %{
        "session_id" => uuid,
        "name" => "fresh session name"
      })

      {:ok, session} = Sessions.get_session_by_uuid(uuid)
      assert session.name == "fresh session name"
    end

    test "sets name when session already exists (pre-registered)", %{conn: _conn} do
      agent = create_agent()
      pre_registered = create_session(agent, %{name: nil})

      post(build_conn(), ~p"/api/v1/sessions", %{
        "session_id" => pre_registered.uuid,
        "name" => "assigned after pre-register"
      })

      {:ok, updated} = Sessions.get_session_by_uuid(pre_registered.uuid)
      assert updated.name == "assigned after pre-register"
    end

    test "does not overwrite existing name when none provided", %{conn: _conn} do
      agent = create_agent()
      session = create_session(agent, %{name: "original name"})

      post(build_conn(), ~p"/api/v1/sessions", %{
        "session_id" => session.uuid
      })

      {:ok, updated} = Sessions.get_session_by_uuid(session.uuid)
      assert updated.name == "original name"
    end

    test "persists description on fresh session create", %{conn: conn} do
      uuid = Ecto.UUID.generate()

      post(conn, ~p"/api/v1/sessions", %{
        "session_id" => uuid,
        "name" => "test session",
        "description" => "doing important work"
      })

      {:ok, session} = Sessions.get_session_by_uuid(uuid)
      assert session.description == "doing important work"
    end

    test "sets description when session already exists", %{conn: _conn} do
      agent = create_agent()
      pre_registered = create_session(agent, %{description: nil})

      post(build_conn(), ~p"/api/v1/sessions", %{
        "session_id" => pre_registered.uuid,
        "name" => "named",
        "description" => "added after pre-register"
      })

      {:ok, updated} = Sessions.get_session_by_uuid(pre_registered.uuid)
      assert updated.description == "added after pre-register"
    end

    test "name and description are independent fields", %{conn: conn} do
      uuid = Ecto.UUID.generate()

      post(conn, ~p"/api/v1/sessions", %{
        "session_id" => uuid,
        "name" => "the name",
        "description" => "the description"
      })

      {:ok, session} = Sessions.get_session_by_uuid(uuid)
      assert session.name == "the name"
      assert session.description == "the description"
      assert session.name != session.description
    end
  end

  # ---- GET /api/v1/sessions/:uuid ----

  describe "GET /api/v1/sessions/:uuid" do
    test "returns session info", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      conn = get(conn, ~p"/api/v1/sessions/#{session.uuid}")
      resp = json_response(conn, 200)

      assert resp["session_id"] == session.uuid
      assert resp["status"] == session.status
      assert resp["initialized"] == true
    end

    test "returns 404 for unknown uuid", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/sessions/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] == "Session not found"
    end

    test "returns tasks linked to the session" do
      agent = create_agent()
      session = create_session(agent)
      task = create_task()
      Tasks.link_session_to_task(task.id, session.id)

      resp = api_conn() |> get(~p"/api/v1/sessions/#{session.uuid}") |> json_response(200)

      assert is_list(resp["tasks"])
      assert Enum.any?(resp["tasks"], &(&1["id"] == task.id))
      assert Enum.all?(resp["tasks"], &Map.has_key?(&1, "state_id"))
    end

    test "returns empty tasks list when none linked" do
      agent = create_agent()
      session = create_session(agent)

      resp = api_conn() |> get(~p"/api/v1/sessions/#{session.uuid}") |> json_response(200)

      assert resp["tasks"] == []
    end

    test "returns recent_notes for the session" do
      agent = create_agent()
      session = create_session(agent)
      create_note(session)

      resp = api_conn() |> get(~p"/api/v1/sessions/#{session.uuid}") |> json_response(200)

      assert is_list(resp["recent_notes"])
      assert length(resp["recent_notes"]) == 1
      assert Map.has_key?(hd(resp["recent_notes"]), "starred")
      assert Map.has_key?(hd(resp["recent_notes"]), "created_at")
    end

    test "truncates note body to 120 chars in recent_notes" do
      agent = create_agent()
      session = create_session(agent)
      long_body = String.duplicate("x", 200)
      create_note(session, %{body: long_body})

      resp = api_conn() |> get(~p"/api/v1/sessions/#{session.uuid}") |> json_response(200)

      note = hd(resp["recent_notes"])
      assert String.length(note["body"]) == 120
    end

    test "caps recent_notes at 5" do
      agent = create_agent()
      session = create_session(agent)
      for _ <- 1..7, do: create_note(session)

      resp = api_conn() |> get(~p"/api/v1/sessions/#{session.uuid}") |> json_response(200)

      assert length(resp["recent_notes"]) == 5
    end

    test "returns recent_commits for the session" do
      agent = create_agent()
      session = create_session(agent)
      commit = create_commit(session)

      resp = api_conn() |> get(~p"/api/v1/sessions/#{session.uuid}") |> json_response(200)

      assert is_list(resp["recent_commits"])
      assert Enum.any?(resp["recent_commits"], &(&1["id"] == commit.id))
      assert Map.has_key?(hd(resp["recent_commits"]), "commit_hash")
      assert Map.has_key?(hd(resp["recent_commits"]), "inserted_at")
    end

    test "caps recent_commits at 5" do
      agent = create_agent()
      session = create_session(agent)
      for _ <- 1..7, do: create_commit(session)

      resp = api_conn() |> get(~p"/api/v1/sessions/#{session.uuid}") |> json_response(200)

      assert length(resp["recent_commits"]) == 5
    end
  end

  # ---- PATCH /api/v1/sessions/:uuid ----

  describe "PATCH /api/v1/sessions/:uuid" do
    test "updates session status to working", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      conn = patch(conn, ~p"/api/v1/sessions/#{session.uuid}", %{"status" => "working"})
      resp = json_response(conn, 200)

      assert resp["uuid"] == session.uuid
      assert resp["status"] == "working"
    end

    test "sets ended_at for terminal status", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      conn = patch(conn, ~p"/api/v1/sessions/#{session.uuid}", %{"status" => "completed"})
      resp = json_response(conn, 200)

      assert resp["status"] == "completed"
      assert resp["ended_at"] != nil
    end

    test "returns 404 for unknown uuid", %{conn: conn} do
      conn = patch(conn, ~p"/api/v1/sessions/#{Ecto.UUID.generate()}", %{"status" => "idle"})
      assert json_response(conn, 404)["error"] == "Session not found"
    end

    test "sets entrypoint to cli", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      patch(conn, ~p"/api/v1/sessions/#{session.uuid}", %{"entrypoint" => "cli"})

      {:ok, updated} = Sessions.get_session_by_uuid(session.uuid)
      assert updated.entrypoint == "cli"
    end

    test "clear_entrypoint true sets entrypoint to nil", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent, %{entrypoint: "cli"})

      patch(conn, ~p"/api/v1/sessions/#{session.uuid}", %{"clear_entrypoint" => true})

      {:ok, updated} = Sessions.get_session_by_uuid(session.uuid)
      assert updated.entrypoint == nil
    end

    test "clear_entrypoint false does not clear entrypoint", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent, %{entrypoint: "cli"})

      patch(conn, ~p"/api/v1/sessions/#{session.uuid}", %{"clear_entrypoint" => false})

      {:ok, updated} = Sessions.get_session_by_uuid(session.uuid)
      assert updated.entrypoint == "cli"
    end

    test "updates session name", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      patch(conn, ~p"/api/v1/sessions/#{session.uuid}", %{"name" => "My Session"})

      {:ok, updated} = Sessions.get_session_by_uuid(session.uuid)
      assert updated.name == "My Session"
    end

    test "updates session description", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      patch(conn, ~p"/api/v1/sessions/#{session.uuid}", %{"description" => "Doing important work"})

      {:ok, updated} = Sessions.get_session_by_uuid(session.uuid)
      assert updated.description == "Doing important work"
    end

    test "updates name and description together", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      patch(conn, ~p"/api/v1/sessions/#{session.uuid}", %{
        "name" => "Combined Update",
        "description" => "Both fields at once"
      })

      {:ok, updated} = Sessions.get_session_by_uuid(session.uuid)
      assert updated.name == "Combined Update"
      assert updated.description == "Both fields at once"
    end

    test "omitting name does not clear existing name", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent, %{name: "Original Name"})

      patch(conn, ~p"/api/v1/sessions/#{session.uuid}", %{"status" => "working"})

      {:ok, updated} = Sessions.get_session_by_uuid(session.uuid)
      assert updated.name == "Original Name"
    end
  end

  # ---- entrypoint on session create ----

  describe "POST /api/v1/sessions entrypoint" do
    test "persists entrypoint on create", %{conn: conn} do
      uuid = Ecto.UUID.generate()

      post(conn, ~p"/api/v1/sessions", %{
        "session_id" => uuid,
        "name" => "cli session",
        "entrypoint" => "cli"
      })

      {:ok, session} = Sessions.get_session_by_uuid(uuid)
      assert session.entrypoint == "cli"
    end

    test "entrypoint defaults to nil when not provided", %{conn: conn} do
      uuid = Ecto.UUID.generate()

      post(conn, ~p"/api/v1/sessions", %{
        "session_id" => uuid,
        "name" => "no entrypoint"
      })

      {:ok, session} = Sessions.get_session_by_uuid(uuid)
      assert session.entrypoint == nil
    end
  end

  # ---- POST /api/v1/sessions/:uuid/end ----

  describe "POST /api/v1/sessions/:uuid/end" do
    test "ends a session with default completed status", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      conn = post(conn, ~p"/api/v1/sessions/#{session.uuid}/end", %{})
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["status"] == "completed"
    end

    test "ends a session with custom final_status", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      conn =
        post(conn, ~p"/api/v1/sessions/#{session.uuid}/end", %{"final_status" => "failed"})

      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["status"] == "failed"
    end

    test "returns 404 for unknown session", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/sessions/#{Ecto.UUID.generate()}/end", %{})
      assert json_response(conn, 404)["error"] == "Session not found"
    end
  end

  # ---- GET /api/v1/sessions/:uuid/context ----

  describe "GET /api/v1/sessions/:uuid/context" do
    test "returns 404 when no context saved", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      conn = get(conn, ~p"/api/v1/sessions/#{session.uuid}/context")
      assert json_response(conn, 404)["error"] == "No context found"
    end

    test "returns context when saved", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      {:ok, _} =
        Contexts.upsert_session_context(%{
          agent_id: agent.id,
          session_id: session.id,
          context: "# My context\nSome details"
        })

      conn = get(conn, ~p"/api/v1/sessions/#{session.uuid}/context")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["context"] == "# My context\nSome details"
    end

    test "returns 404 for unknown session", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/sessions/#{Ecto.UUID.generate()}/context")
      assert json_response(conn, 404)["error"] == "Session not found"
    end
  end

  # ---- PATCH /api/v1/sessions/:uuid/context ----

  describe "PATCH /api/v1/sessions/:uuid/context" do
    test "saves session context", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      conn =
        patch(conn, ~p"/api/v1/sessions/#{session.uuid}/context", %{
          "context" => "# Context\nImportant stuff"
        })

      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["context"] == "# Context\nImportant stuff"
    end

    test "upserts existing context", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)

      patch(conn, ~p"/api/v1/sessions/#{session.uuid}/context", %{"context" => "first"})

      conn2 =
        patch(build_conn(), ~p"/api/v1/sessions/#{session.uuid}/context", %{
          "context" => "second"
        })

      resp = json_response(conn2, 200)
      assert resp["context"] == "second"
    end

    test "returns 400 when context is missing", %{conn: conn} do
      agent = create_agent()
      session = create_session(agent)
      conn = patch(conn, ~p"/api/v1/sessions/#{session.uuid}/context", %{})
      assert json_response(conn, 400)["error"] == "context is required"
    end

    test "returns 404 for unknown session", %{conn: conn} do
      conn =
        patch(conn, ~p"/api/v1/sessions/#{Ecto.UUID.generate()}/context", %{
          "context" => "stuff"
        })

      assert json_response(conn, 404)["error"] == "Session not found"
    end
  end
end
