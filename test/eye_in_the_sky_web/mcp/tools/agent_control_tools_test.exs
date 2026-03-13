defmodule EyeInTheSkyWeb.MCP.Tools.AgentControlToolsTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.{AgentCancel, AgentStatus}
  alias EyeInTheSkyWeb.{Agents, Sessions}

  @frame :test_frame

  defp json_result({:reply, %Anubis.Server.Response{content: [%{"text" => json} | _]}, @frame}) do
    Jason.decode!(json, keys: :atoms)
  end

  defp uniq, do: System.unique_integer([:positive])

  defp new_session do
    {:ok, agent} = Agents.create_agent(%{name: "ctrl-agent-#{uniq()}", status: "active"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "idle"
      })

    session
  end

  # ---- AgentStatus ----

  test "AgentStatus: no_worker when no worker running" do
    session = new_session()
    r = AgentStatus.execute(%{session_id: to_string(session.id)}, @frame) |> json_result()
    assert r.success == true
    assert r.status == "no_worker"
    assert r.processing == false
  end

  test "AgentStatus: idle after worker started but not processing" do
    session = new_session()
    # send a message to start the worker, then check immediately — cast is async so worker will be idle
    EyeInTheSkyWeb.Claude.AgentManager.send_message(session.id, "test", [])
    r = AgentStatus.execute(%{session_id: session.uuid}, @frame) |> json_result()
    assert r.success == true
    assert r.session_id == session.id
    assert r.status in ["idle", "processing"]
  end

  test "AgentStatus: error for nonexistent UUID" do
    r = AgentStatus.execute(%{session_id: Ecto.UUID.generate()}, @frame) |> json_result()
    assert r.success == false
    assert String.contains?(r.message, "not found")
  end

  # ---- AgentCancel ----

  test "AgentCancel: no_worker message when worker not running" do
    session = new_session()
    r = AgentCancel.execute(%{session_id: to_string(session.id)}, @frame) |> json_result()
    assert r.success == false
    assert String.contains?(r.message, "No active worker")
  end

  test "AgentCancel: cancels running worker" do
    session = new_session()
    EyeInTheSkyWeb.Claude.AgentManager.send_message(session.id, "long task", [])
    r = AgentCancel.execute(%{session_id: session.uuid}, @frame) |> json_result()
    assert r.success == true
    assert String.contains?(r.message, "Cancelled")
  end

  test "AgentCancel: error for nonexistent UUID" do
    r = AgentCancel.execute(%{session_id: Ecto.UUID.generate()}, @frame) |> json_result()
    assert r.success == false
    assert String.contains?(r.message, "not found")
  end
end
