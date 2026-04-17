defmodule EyeInTheSkyWeb.Api.V1.IAMControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSky.Repo

  import Ecto.Query

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

  setup do
    {:ok, conn: api_conn()}
  end

  # ── basic routing + auth ────────────────────────────────────────────────────

  test "rejects unauthenticated requests", %{conn: _conn} do
    conn = Phoenix.ConnTest.build_conn()
    conn = post(conn, "/api/v1/iam/decide", bash_pre_tool_use_payload())
    assert conn.status == 401
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
    {:ok, project} =
      Repo.insert(%EyeInTheSky.Projects.Project{
        id: System.unique_integer([:positive, :monotonic]),
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

    # Give the fire-and-forget task time to complete
    :timer.sleep(200)

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
end
