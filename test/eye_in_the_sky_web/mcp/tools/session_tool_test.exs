defmodule EyeInTheSkyWeb.MCP.Tools.SessionToolTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.Session, as: SessionTool
  alias EyeInTheSkyWeb.MCP.Tools.EndSession
  alias EyeInTheSkyWeb.MCP.Tools.SessionInfo
  alias EyeInTheSkyWeb.MCP.Tools.SessionSearch
  alias EyeInTheSkyWeb.{Agents, Sessions}

  @frame :test_frame

  defp json_result({:reply, %Anubis.Server.Response{content: [%{"text" => json} | _]}, @frame}) do
    Jason.decode!(json, keys: :atoms)
  end

  defp new_session do
    {:ok, agent} = Agents.create_agent(%{name: "test-agent-#{uniq()}", status: "working"})
    {:ok, session} = Sessions.create_session(%{
      uuid: "sess-#{uniq()}",
      agent_id: agent.id,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      status: "working"
    })
    session
  end

  defp uniq, do: System.unique_integer([:positive])

  # ---- Session tool ----

  test "start: creates a new session" do
    uuid = "new-#{uniq()}"
    r = SessionTool.execute(%{command: "start", session_id: uuid}, @frame) |> json_result()
    assert r.success == true
    assert r.session_id == uuid
    assert is_integer(r.session_int_id)
  end

  test "start: creates default agent when no agents exist (nil-agent fallback path)" do
    # This exercises the create_or_find_session fallback: Agents.list_active_agents()
    # returns [] in a clean sandbox, so the tool must create a default agent.
    # Before the fix, Agents.create_agent returning {:error, _} would crash
    # the GenServer via a bare pattern match; now it returns a graceful error.
    uuid = "nil-agent-#{uniq()}"
    r = SessionTool.execute(%{command: "start", session_id: uuid}, @frame) |> json_result()
    assert r.success == true
    assert r.session_id == uuid
    assert is_integer(r.session_int_id)
  end

  test "start: returns existing session when uuid already exists" do
    s = new_session()
    r = SessionTool.execute(%{command: "start", session_id: s.uuid}, @frame) |> json_result()
    assert r.success == true
    assert r.session_id == s.uuid
  end

  test "end: ends an active session" do
    s = new_session()
    r = SessionTool.execute(%{command: "end", session_id: s.uuid}, @frame) |> json_result()
    assert r.success == true
  end

  test "end: returns error for nonexistent session" do
    r = SessionTool.execute(%{command: "end", session_id: "ghost-uuid"}, @frame) |> json_result()
    assert r.success == false
  end

  test "update: updates session status" do
    s = new_session()
    r = SessionTool.execute(%{command: "update", session_id: s.uuid, status: "idle"}, @frame) |> json_result()
    assert r.success == true
  end

  test "info: returns session info" do
    s = new_session()
    r = SessionTool.execute(%{command: "info", session_id: s.uuid}, @frame) |> json_result()
    assert r.success == true
    assert r.initialized == true
    assert r.session_id == s.uuid
  end

  test "info: returns not_found for unknown session" do
    r = SessionTool.execute(%{command: "info", session_id: "ghost"}, @frame) |> json_result()
    assert r.success == false
    assert r.initialized == false
  end

  test "search: returns sessions list" do
    new_session()
    r = SessionTool.execute(%{command: "search", query: ""}, @frame) |> json_result()
    assert r.success == true
    assert is_list(r.results)
  end

  test "unknown command: returns error response" do
    {:reply, response, @frame} = SessionTool.execute(%{command: "bogus"}, @frame)
    assert response.isError == true
  end

  # ---- EndSession tool ----

  test "EndSession: ends session by agent_id UUID" do
    s = new_session()
    r = EndSession.execute(%{agent_id: s.uuid}, @frame) |> json_result()
    assert r.success == true
  end

  test "EndSession: error for unknown UUID" do
    r = EndSession.execute(%{agent_id: "unknown"}, @frame) |> json_result()
    assert r.success == false
    assert String.contains?(r.message, "not found")
  end

  # ---- SessionInfo tool ----

  test "SessionInfo: returns info for known session" do
    s = new_session()
    r = SessionInfo.execute(%{session_id: s.uuid}, @frame) |> json_result()
    assert r.initialized == true
    assert r.session_id == s.uuid
  end

  test "SessionInfo: not initialized for unknown session" do
    r = SessionInfo.execute(%{session_id: "ghost"}, @frame) |> json_result()
    assert r.initialized == false
  end

  test "SessionInfo: not initialized when no session_id given" do
    r = SessionInfo.execute(%{}, @frame) |> json_result()
    assert r.initialized == false
    assert r.session_id == nil
  end

  # ---- SessionSearch tool ----

  test "SessionSearch: returns list" do
    new_session()
    r = SessionSearch.execute(%{query: ""}, @frame) |> json_result()
    assert r.success == true
    assert is_list(r.results)
  end

  test "SessionSearch: respects limit" do
    {:ok, agent} = Agents.create_agent(%{name: "limit-agent-#{uniq()}", status: "active"})
    for _ <- 1..5 do
      Sessions.create_session(%{
        uuid: "lim-#{uniq()}",
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "idle"
      })
    end
    r = SessionSearch.execute(%{query: "", limit: 2}, @frame) |> json_result()
    assert length(r.results) <= 2
  end
end
