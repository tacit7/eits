defmodule EyeInTheSkyWeb.Api.V1.IAMControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.Repo

  import Ecto.Query
  import EyeInTheSky.Factory

  defp api_conn do
    token = "test_iam_key_#{System.unique_integer([:positive])}"
    {:ok, _} = ApiKey.create(token, "iam-test")
    Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  defp bash_pre_tool_use_payload(overrides \\ %{}) do
    Map.merge(
      %{
        "hook_event_name" => "PreToolUse",
        "tool_name" => "Bash",
        "tool_input" => %{"command" => "ls -la"},
        "session_id" => Ecto.UUID.generate(),
        "cwd" => "/tmp/test-project"
      },
      overrides
    )
  end

  defp stop_event_payload(overrides \\ %{}) do
    Map.merge(
      %{
        "hook_event_name" => "Stop",
        "session_id" => Ecto.UUID.generate(),
        "reason" => "user_requested",
        "cwd" => "/tmp/test-project"
      },
      overrides
    )
  end

  setup do
    {:ok, conn: api_conn()}
  end

  # ── basic routing + auth ────────────────────────────────────────────────────

  # The IAM decide endpoint is intentionally unauthenticated — it is called by Claude CLI
  # hooks which run without user sessions (see router.ex :accepts_json pipeline).
  # This test previously asserted a 401, but the endpoint is designed to be open.
  test "IAM decide endpoint is accessible without auth (intentionally unauthenticated)", %{
    conn: _conn
  } do
    conn = Phoenix.ConnTest.build_conn()
    conn = post(conn, "/api/v1/iam/decide", bash_pre_tool_use_payload())
    assert conn.status == 200
  end

  # ── allow decision (no policies → fallback allow) ───────────────────────────

  test "returns allow permissionDecision for fallback allow", %{conn: conn} do
    payload = bash_pre_tool_use_payload()
    conn = post(conn, "/api/v1/iam/decide", payload)

    assert conn.status == 200
    body = json_response(conn, 200)

    assert body["continue"] == true
    assert get_in(body, ["hookSpecificOutput", "hookEventName"]) == "PreToolUse"
    assert get_in(body, ["hookSpecificOutput", "permissionDecision"]) == "allow"
  end

  # ── deny decision ────────────────────────────────────────────────────────────

  test "returns deny permissionDecision when a deny policy matches", %{conn: conn} do
    project =
      project_fixture(%{
        name: "iam-test-project-#{System.unique_integer()}",
        path: "/tmp/iam-test-#{System.unique_integer()}"
      })

    {:ok, _policy} =
      Repo.insert(%EyeInTheSky.IAM.Policy{
        name: "deny-ls",
        effect: "deny",
        agent_type: "*",
        action: "Bash",
        resource_glob: "ls*",
        project_id: project.id,
        priority: 100,
        enabled: true,
        message: "ls is blocked",
        condition: %{}
      })

    EyeInTheSky.IAM.PolicyCache.invalidate()

    payload =
      bash_pre_tool_use_payload(%{
        "tool_input" => %{"command" => "ls -la"},
        "cwd" => project.path
      })

    conn = post(conn, "/api/v1/iam/decide", payload)

    assert conn.status == 200
    body = json_response(conn, 200)

    assert get_in(body, ["hookSpecificOutput", "permissionDecision"]) == "deny"
    assert get_in(body, ["hookSpecificOutput", "permissionDecisionReason"]) =~ "ls is blocked"
  end

  # ── audit row insertion ──────────────────────────────────────────────────────

  test "inserts an iam_decisions row after processing", %{conn: conn} do
    session_uuid = Ecto.UUID.generate()
    payload = bash_pre_tool_use_payload(%{"session_id" => session_uuid})

    before_count = Repo.one(from d in "iam_decisions", select: count(d.id))

    conn = post(conn, "/api/v1/iam/decide", payload)
    assert conn.status == 200

    after_count = Repo.one(from d in "iam_decisions", select: count(d.id))
    assert after_count == before_count + 1

    session_uuid_bin = Ecto.UUID.dump!(session_uuid)

    row =
      Repo.one(
        from d in "iam_decisions",
          where: d.session_uuid == ^session_uuid_bin,
          order_by: [desc: d.inserted_at],
          limit: 1,
          select: %{
            event: d.event,
            tool: d.tool,
            permission: d.permission,
            duration_us: d.duration_us
          }
      )

    assert row.event == "pre_tool_use"
    assert row.tool == "Bash"
    assert row.permission == "allow"
    assert is_integer(row.duration_us) and row.duration_us > 0
  end

  # ── PostToolUse event ───────────────────────────────────────────────────────

  test "returns continue: true for PostToolUse allow with no instructions", %{conn: conn} do
    payload = %{
      "hook_event_name" => "PostToolUse",
      "tool_name" => "Bash",
      "tool_input" => %{"command" => "echo hi"},
      "session_id" => Ecto.UUID.generate(),
      "cwd" => "/tmp"
    }

    conn = post(conn, "/api/v1/iam/decide", payload)
    body = json_response(conn, 200)

    assert body["continue"] == true
    refute Map.has_key?(body, "hookSpecificOutput")
  end

  # ── sanitize_api_keys PostToolUse ───────────────────────────────────────────

  describe "sanitize_api_keys builtin on PostToolUse" do
    setup do
      {:ok, _} =
        EyeInTheSky.IAM.seed_builtin(%{
          system_key: "builtin.sanitize_api_keys",
          name: "Sanitize API keys in output",
          effect: "instruct",
          action: "*",
          event: "PostToolUse",
          builtin_matcher: "sanitize_api_keys",
          priority: 100,
          message: "Tool output has been scanned and secrets redacted.",
          editable_fields: ["enabled"]
        })

      EyeInTheSky.IAM.PolicyCache.invalidate()
      :ok
    end

    test "redacts Anthropic key in tool_response and returns sanitized additionalContext",
         %{conn: conn} do
      payload = %{
        "hook_event_name" => "PostToolUse",
        "tool_name" => "Bash",
        "tool_input" => %{"command" => "cat secrets.txt"},
        "tool_response" => "my key is sk-ant-abcdefghij1234567890 done",
        "session_id" => Ecto.UUID.generate(),
        "cwd" => "/tmp"
      }

      conn = post(conn, "/api/v1/iam/decide", payload)
      body = json_response(conn, 200)

      assert body["continue"] == true
      assert body["suppressOutput"] == true
      assert get_in(body, ["hookSpecificOutput", "hookEventName"]) == "PostToolUse"

      ctx = get_in(body, ["hookSpecificOutput", "additionalContext"])
      assert is_binary(ctx)
      assert String.contains?(ctx, "[REDACTED:anthropic]")
      refute String.contains?(ctx, "sk-ant-")
    end

    test "PostToolUse without secrets continues without hookSpecificOutput", %{conn: conn} do
      payload = %{
        "hook_event_name" => "PostToolUse",
        "tool_name" => "Bash",
        "tool_input" => %{"command" => "echo hi"},
        "tool_response" => "hi",
        "session_id" => Ecto.UUID.generate(),
        "cwd" => "/tmp"
      }

      conn = post(conn, "/api/v1/iam/decide", payload)
      body = json_response(conn, 200)

      assert body["continue"] == true
      refute Map.has_key?(body, "hookSpecificOutput")
    end

    test "sanitize_api_keys policy does not fire on PreToolUse events", %{conn: conn} do
      payload = %{
        "hook_event_name" => "PreToolUse",
        "tool_name" => "Bash",
        "tool_input" => %{"command" => "echo sk-ant-abcdefghij1234567890"},
        "session_id" => Ecto.UUID.generate(),
        "cwd" => "/tmp"
      }

      conn = post(conn, "/api/v1/iam/decide", payload)
      body = json_response(conn, 200)

      # Should return PreToolUse shape — the sanitize policy did not match
      assert body["continue"] == true
      assert get_in(body, ["hookSpecificOutput", "hookEventName"]) == "PreToolUse"
      additional = get_in(body, ["hookSpecificOutput", "additionalContext"]) || ""
      refute String.contains?(additional, "[REDACTED:anthropic]")
    end
  end

  # ── Stop event ──────────────────────────────────────────────────────────────

  test "returns continue: true for Stop allow (no instructions)", %{conn: conn} do
    payload = stop_event_payload()
    conn = post(conn, "/api/v1/iam/decide", payload)

    assert conn.status == 200
    body = json_response(conn, 200)
    assert body["continue"] == true
    refute Map.has_key?(body, "hookSpecificOutput")
  end

  test "returns continue: false (stopReason) for Stop deny", %{conn: conn} do
    project =
      project_fixture(%{
        name: "iam-test-stop-#{System.unique_integer()}",
        path: "/tmp/iam-test-stop-#{System.unique_integer()}"
      })

    {:ok, _policy} =
      Repo.insert(%EyeInTheSky.IAM.Policy{
        name: "deny-stop",
        effect: "deny",
        event: "Stop",
        agent_type: "*",
        action: "*",
        project_id: project.id,
        priority: 100,
        enabled: true,
        message: "Stop denied",
        condition: %{}
      })

    EyeInTheSky.IAM.PolicyCache.invalidate()

    payload =
      stop_event_payload(%{
        "cwd" => project.path
      })

    conn = post(conn, "/api/v1/iam/decide", payload)
    body = json_response(conn, 200)

    assert body["continue"] == false
    assert body["stopReason"] =~ "Stop denied"
  end

  test "returns additionalContext for Stop instruct", %{conn: conn} do
    project =
      project_fixture(%{
        name: "iam-test-instruct-#{System.unique_integer()}",
        path: "/tmp/iam-test-instruct-#{System.unique_integer()}"
      })

    {:ok, _policy} =
      Repo.insert(%EyeInTheSky.IAM.Policy{
        name: "instruct-stop",
        effect: "instruct",
        event: "Stop",
        agent_type: "*",
        action: "*",
        project_id: project.id,
        priority: 100,
        enabled: true,
        message: "Session ended cleanly.",
        condition: %{}
      })

    EyeInTheSky.IAM.PolicyCache.invalidate()

    payload =
      stop_event_payload(%{
        "cwd" => project.path
      })

    conn = post(conn, "/api/v1/iam/decide", payload)
    body = json_response(conn, 200)

    assert body["continue"] == true
    assert body["suppressOutput"] == true
    assert get_in(body, ["hookSpecificOutput", "hookEventName"]) == "Stop"

    assert String.contains?(
             get_in(body, ["hookSpecificOutput", "additionalContext"]) || "",
             "Session ended cleanly"
           )
  end

  test "Stop event inserted in iam_decisions audit row", %{conn: conn} do
    session_uuid = Ecto.UUID.generate()
    payload = stop_event_payload(%{"session_id" => session_uuid})

    before_count = Repo.one(from d in "iam_decisions", select: count(d.id))

    conn = post(conn, "/api/v1/iam/decide", payload)
    assert conn.status == 200

    after_count = Repo.one(from d in "iam_decisions", select: count(d.id))
    assert after_count == before_count + 1

    session_uuid_bin = Ecto.UUID.dump!(session_uuid)

    row =
      Repo.one(
        from d in "iam_decisions",
          where: d.session_uuid == ^session_uuid_bin,
          order_by: [desc: d.inserted_at],
          limit: 1,
          select: %{event: d.event, permission: d.permission}
      )

    assert row.event == "stop"
    assert row.permission == "allow"
  end
end
