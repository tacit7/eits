defmodule EyeInTheSkyWeb.MCP.Tools.CommitsToolTest do
  @moduledoc """
  Tests for the Commits MCP tool, focusing on the integer agent_id resolution
  path that was previously broken.
  """
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.Commits
  alias EyeInTheSkyWeb.Agents
  alias EyeInTheSkyWeb.Sessions
  alias EyeInTheSkyWeb.Commits, as: CommitsCtx

  @frame :test_frame

  import EyeInTheSkyWeb.Factory

  defp new_agent_and_session do
    {:ok, agent} = Agents.create_agent(%{name: "commit-agent-#{uniq()}", status: "idle"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: "commit-sess-#{uniq()}",
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "working"
      })

    {agent, session}
  end

  # ---- Integer agent_id resolution (the bug fix) ----

  test "resolves integer agent_id to session and logs commits" do
    {agent, _session} = new_agent_and_session()

    r =
      Commits.execute(
        %{
          agent_id: to_string(agent.id),
          commit_hashes: ["aaa111", "bbb222"],
          commit_messages: ["first", "second"]
        },
        @frame
      )
      |> json_result()

    assert r.success == true
    assert r.message == "Logged 2/2 commits"
  end

  test "integer agent_id with no sessions resolves to nil session" do
    {:ok, agent} = Agents.create_agent(%{name: "lonely-agent-#{uniq()}", status: "idle"})

    r =
      Commits.execute(
        %{
          agent_id: to_string(agent.id),
          commit_hashes: ["ccc333"],
          commit_messages: ["orphan"]
        },
        @frame
      )
      |> json_result()

    # nil guard: agent with no sessions cannot be resolved, returns error
    assert r.success == false
    assert String.contains?(r.message, "Could not resolve session")
  end

  test "integer agent_id picks the most recent session" do
    {:ok, agent} = Agents.create_agent(%{name: "multi-sess-#{uniq()}", status: "idle"})

    {:ok, _old_session} =
      Sessions.create_session(%{
        uuid: "old-#{uniq()}",
        agent_id: agent.id,
        started_at: "2020-01-01T00:00:00Z",
        status: "completed"
      })

    {:ok, new_session} =
      Sessions.create_session(%{
        uuid: "new-#{uniq()}",
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "working"
      })

    r =
      Commits.execute(
        %{
          agent_id: to_string(agent.id),
          commit_hashes: ["ddd444"],
          commit_messages: ["latest"]
        },
        @frame
      )
      |> json_result()

    assert r.success == true
    assert r.message == "Logged 1/1 commits"

    # Verify commit was linked to the newer session
    commits = CommitsCtx.list_commits()
    commit = Enum.find(commits, &(&1.commit_hash == "ddd444"))
    assert commit != nil
    assert commit.session_id == new_session.id
  end

  # ---- UUID agent_id path ----

  test "UUID agent_id resolves via get_session_by_uuid" do
    {_agent, session} = new_agent_and_session()

    r =
      Commits.execute(
        %{
          agent_id: session.uuid,
          commit_hashes: ["eee555"],
          commit_messages: ["by uuid"]
        },
        @frame
      )
      |> json_result()

    assert r.success == true
    assert r.message == "Logged 1/1 commits"
  end

  # ---- Edge cases ----

  test "commit_messages defaults to empty strings when not provided" do
    {_agent, session} = new_agent_and_session()

    r =
      Commits.execute(
        %{
          agent_id: session.uuid,
          commit_hashes: ["fff666", "ggg777"]
        },
        @frame
      )
      |> json_result()

    assert r.success == true
    assert r.message == "Logged 2/2 commits"
  end

  test "fewer messages than hashes fills missing with empty string" do
    {_agent, session} = new_agent_and_session()

    r =
      Commits.execute(
        %{
          agent_id: session.uuid,
          commit_hashes: ["hhh888", "iii999", "jjj000"],
          commit_messages: ["only one"]
        },
        @frame
      )
      |> json_result()

    assert r.success == true
    assert r.message == "Logged 3/3 commits"
  end
end
