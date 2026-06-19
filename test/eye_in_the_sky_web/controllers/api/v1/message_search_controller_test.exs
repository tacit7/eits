defmodule EyeInTheSkyWeb.Api.V1.MessageSearchControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.{Messages, Sessions}

  import EyeInTheSky.Factory

  # Auth is bypassed in test env (api_key: nil in config/test.exs).
  # Build a plain conn — no Bearer token required.
  defp api_conn, do: Phoenix.ConnTest.build_conn()

  defp create_session_with_agent(overrides \\ %{}) do
    agent = create_agent()
    create_session(agent, overrides)
  end

  defp create_message(session, body, overrides \\ %{}) do
    now = DateTime.utc_now()

    {:ok, msg} =
      Messages.create_message(
        Map.merge(
          %{
            session_id: session.id,
            sender_role: "user",
            direction: "inbound",
            body: body,
            inserted_at: now,
            updated_at: now
          },
          overrides
        )
      )

    msg
  end

  # ---- GET /api/v1/messages/search ----

  describe "GET /api/v1/messages/search" do
    test "returns matching messages for a valid query", %{conn: _conn} do
      conn = api_conn()
      session = create_session_with_agent()
      create_message(session, "elixir phoenix is amazing for web development")

      response =
        conn
        |> get("/api/v1/messages/search?q=elixir")
        |> json_response(200)

      assert response["success"] == true
      assert response["query"] == "elixir"
      assert response["count"] >= 1

      msg = Enum.find(response["messages"], &String.contains?(&1["body_excerpt"], "elixir"))
      assert msg != nil
      assert msg["session_id"] == session.id
      assert Map.has_key?(msg, "role")
      assert Map.has_key?(msg, "body_excerpt")
      assert Map.has_key?(msg, "inserted_at")
    end

    test "returns empty results when no messages match the query", %{conn: _conn} do
      conn = api_conn()
      session = create_session_with_agent()
      create_message(session, "something completely unrelated content here")

      response =
        conn
        |> get("/api/v1/messages/search?q=xyzzynonexistenttermzzz")
        |> json_response(200)

      assert response["success"] == true
      assert response["count"] == 0
      assert response["messages"] == []
    end

    test "returns 400 when q param is missing", %{conn: _conn} do
      conn = api_conn()

      response =
        conn
        |> get("/api/v1/messages/search")
        |> json_response(400)

      assert response["error"] =~ "q is required"
    end

    test "returns 400 when q param is empty string", %{conn: _conn} do
      conn = api_conn()

      response =
        conn
        |> get("/api/v1/messages/search?q=")
        |> json_response(400)

      assert response["error"] =~ "q is required"
    end

    test "returns 400 when q param is whitespace only", %{conn: _conn} do
      conn = api_conn()

      response =
        conn
        |> get("/api/v1/messages/search?q=   ")
        |> json_response(400)

      assert response["error"] =~ "q is required"
    end

    test "scopes results to session_id when provided as integer", %{conn: _conn} do
      conn = api_conn()
      session_a = create_session_with_agent()
      session_b = create_session_with_agent()

      create_message(session_a, "unique phoenix liveview query term alpha")
      create_message(session_b, "unique phoenix liveview query term beta")

      response =
        conn
        |> get("/api/v1/messages/search?q=phoenix&session_id=#{session_a.id}")
        |> json_response(200)

      assert response["success"] == true
      assert Enum.all?(response["messages"], &(&1["session_id"] == session_a.id))
      refute Enum.any?(response["messages"], &(&1["session_id"] == session_b.id))
    end

    test "scopes results to session_id when provided as UUID", %{conn: _conn} do
      conn = api_conn()
      session_a = create_session_with_agent()
      session_b = create_session_with_agent()

      create_message(session_a, "elixir ecto changeset testing unique alpha")
      create_message(session_b, "elixir ecto changeset testing unique beta")

      response =
        conn
        |> get("/api/v1/messages/search?q=ecto&session_id=#{session_a.uuid}")
        |> json_response(200)

      assert response["success"] == true
      assert Enum.all?(response["messages"], &(&1["session_id"] == session_a.id))
      refute Enum.any?(response["messages"], &(&1["session_id"] == session_b.id))
    end

    test "returns 404 when session_id does not exist", %{conn: _conn} do
      conn = api_conn()

      response =
        conn
        |> get("/api/v1/messages/search?q=anything&session_id=99999999")
        |> json_response(404)

      assert response["error"] =~ "session not found"
    end

    test "respects limit param", %{conn: _conn} do
      conn = api_conn()
      session = create_session_with_agent()

      for i <- 1..5 do
        create_message(session, "searchable common term repeated entry number #{i}")
      end

      response =
        conn
        |> get("/api/v1/messages/search?q=searchable&limit=2")
        |> json_response(200)

      assert response["success"] == true
      assert length(response["messages"]) <= 2
    end

    test "caps limit at 100", %{conn: _conn} do
      conn = api_conn()

      # Just verify the endpoint accepts limit=200 without error (capped internally)
      response =
        conn
        |> get("/api/v1/messages/search?q=anything&limit=200")
        |> json_response(200)

      assert response["success"] == true
      assert length(response["messages"]) <= 100
    end

    test "uses default limit of 10 when not specified", %{conn: _conn} do
      conn = api_conn()
      session = create_session_with_agent()

      for i <- 1..15 do
        create_message(session, "defaultlimit common searchterm entry number #{i}")
      end

      response =
        conn
        |> get("/api/v1/messages/search?q=defaultlimit")
        |> json_response(200)

      assert response["success"] == true
      assert length(response["messages"]) <= 10
    end

    test "excludes messages from archived sessions by default", %{conn: _conn} do
      conn = api_conn()
      session = create_session_with_agent()
      create_message(session, "archivedterm unique content for testing archival")

      # Archive the session
      {:ok, _} = Sessions.update_session(session, %{archived_at: DateTime.utc_now()})

      response =
        conn
        |> get("/api/v1/messages/search?q=archivedterm")
        |> json_response(200)

      assert response["success"] == true
      assert Enum.all?(response["messages"], &(&1["session_id"] != session.id))
    end

    test "includes messages from archived sessions when include_archived=true", %{conn: _conn} do
      conn = api_conn()
      session = create_session_with_agent()
      create_message(session, "includearchived unique content for testing visibility")

      # Archive the session
      {:ok, _} = Sessions.update_session(session, %{archived_at: DateTime.utc_now()})

      response =
        conn
        |> get("/api/v1/messages/search?q=includearchived&include_archived=true")
        |> json_response(200)

      assert response["success"] == true
      assert Enum.any?(response["messages"], &(&1["session_id"] == session.id))
    end

    test "returns session_uuid and session_name in each message result", %{conn: _conn} do
      conn = api_conn()
      session = create_session_with_agent(%{name: "My Named Session"})
      create_message(session, "sessionmetadata unique query content term here")

      response =
        conn
        |> get("/api/v1/messages/search?q=sessionmetadata")
        |> json_response(200)

      assert response["count"] >= 1
      msg = hd(response["messages"])
      assert msg["session_uuid"] == session.uuid
      assert msg["session_name"] == "My Named Session"
    end

    test "ignores empty session_id param", %{conn: _conn} do
      conn = api_conn()
      session = create_session_with_agent()
      create_message(session, "emptysessionid unique term content check")

      response =
        conn
        |> get("/api/v1/messages/search?q=emptysessionid&session_id=")
        |> json_response(200)

      assert response["success"] == true
      assert response["count"] >= 1
    end

    test "only returns messages with searchable sender_role (user/agent/assistant)", %{
      conn: _conn
    } do
      conn = api_conn()
      session = create_session_with_agent()
      # Create messages with all three valid roles
      create_message(session, "rolecheck unique term alpha", %{sender_role: "user"})
      create_message(session, "rolecheck unique term beta", %{sender_role: "assistant"})
      create_message(session, "rolecheck unique term gamma", %{sender_role: "agent"})

      response =
        conn
        |> get("/api/v1/messages/search?q=rolecheck")
        |> json_response(200)

      assert response["success"] == true
      assert response["count"] >= 3
      roles = Enum.map(response["messages"], & &1["role"])
      assert Enum.all?(roles, &(&1 in ["user", "agent", "assistant"]))
    end
  end
end
