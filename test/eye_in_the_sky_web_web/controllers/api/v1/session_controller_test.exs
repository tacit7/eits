defmodule EyeInTheSkyWebWeb.Api.V1.SessionControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  alias EyeInTheSkyWeb.{Contexts, Sessions}

  import EyeInTheSkyWeb.Factory

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
