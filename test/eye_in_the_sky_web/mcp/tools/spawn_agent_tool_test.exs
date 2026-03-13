defmodule EyeInTheSkyWeb.MCP.Tools.SpawnAgentToolTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.SpawnAgent
  alias EyeInTheSkyWeb.{Agents, Projects, Sessions}

  @frame :test_frame

  defp json_result({:reply, %Anubis.Server.Response{content: [%{"text" => json} | _]}, @frame}) do
    Jason.decode!(json, keys: :atoms)
  end

  defp uniq, do: System.unique_integer([:positive])

  test "spawns agent and returns session_id, session_uuid, agent_id" do
    r = SpawnAgent.execute(%{instructions: "say hello"}, @frame) |> json_result()
    assert r.success == true
    assert is_integer(r.session_id)
    assert is_binary(r.session_uuid)
    assert is_binary(r.agent_id)
  end

  test "associates agent with project when project_id given" do
    {:ok, project} = Projects.create_project(%{name: "proj-#{uniq()}"})
    r = SpawnAgent.execute(%{instructions: "task", project_id: project.id}, @frame) |> json_result()
    assert r.success == true

    {:ok, session} = Sessions.get_session(r.session_id)
    assert session.project_id == project.id
  end

  test "sets provider to codex when specified" do
    r = SpawnAgent.execute(%{instructions: "task", provider: "codex"}, @frame) |> json_result()
    assert r.success == true

    {:ok, session} = Sessions.get_session(r.session_id)
    assert session.provider == "codex"
  end

  test "defaults to claude provider" do
    r = SpawnAgent.execute(%{instructions: "task"}, @frame) |> json_result()
    assert r.success == true

    {:ok, session} = Sessions.get_session(r.session_id)
    assert session.provider == "claude"
  end

  test "stores project_path as git_worktree_path on session" do
    r = SpawnAgent.execute(%{instructions: "task", project_path: "/tmp/myproject"}, @frame) |> json_result()
    assert r.success == true

    {:ok, session} = Sessions.get_session(r.session_id)
    assert session.git_worktree_path == "/tmp/myproject"
  end

  test "stores parent_agent_id and parent_session_id on agent and session" do
    {:ok, parent_agent} = Agents.create_agent(%{name: "parent-#{uniq()}", status: "active"})
    {:ok, parent_session} = Sessions.create_session(%{
      uuid: Ecto.UUID.generate(),
      agent_id: parent_agent.id,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      status: "idle"
    })

    r = SpawnAgent.execute(%{
      instructions: "child task",
      parent_agent_id: parent_agent.id,
      parent_session_id: parent_session.id
    }, @frame) |> json_result()

    assert r.success == true

    {:ok, session} = Sessions.get_session(r.session_id)
    assert session.parent_agent_id == parent_agent.id
    assert session.parent_session_id == parent_session.id
  end
end
