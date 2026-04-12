defmodule EyeInTheSky.SessionsTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import EyeInTheSky.Factory

  alias EyeInTheSky.{Commits, Logs, Messages, Notes, Sessions, Tasks}
  alias EyeInTheSky.Sessions.Queries
  alias EyeInTheSky.Tasks.WorkflowState

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_task(overrides \\ %{}) do
    {:ok, task} =
      Tasks.create_task(
        Map.merge(%{title: "task_#{System.unique_integer([:positive])}", state_id: 1}, overrides)
      )

    task
  end

  defp in_progress_task(overrides \\ %{}) do
    state_id = WorkflowState.in_progress_id()
    create_task(Map.put(overrides, :state_id, state_id))
  end

  # ---------------------------------------------------------------------------
  # register_from_hook/2
  # ---------------------------------------------------------------------------

  describe "register_from_hook/2" do
    test "creates agent and session from hook params" do
      uuid = Ecto.UUID.generate()

      params = %{
        "session_id" => uuid,
        "description" => "test session",
        "provider" => "claude"
      }

      assert {:ok, %{session: session, agent: agent}} =
               Sessions.register_from_hook(params, nil)

      assert session.uuid == uuid
      assert session.status == "working"
      assert session.agent_id == agent.id
      assert agent.uuid == uuid
    end

    test "uses agent_id param when provided" do
      session_uuid = Ecto.UUID.generate()
      agent_uuid = Ecto.UUID.generate()

      params = %{
        "session_id" => session_uuid,
        "agent_id" => agent_uuid,
        "description" => "test"
      }

      assert {:ok, %{agent: agent}} = Sessions.register_from_hook(params, nil)
      assert agent.uuid == agent_uuid
    end

    test "creates session with model info when model string is provided" do
      uuid = Ecto.UUID.generate()

      params = %{
        "session_id" => uuid,
        "description" => "test",
        "model" => "claude-sonnet-4-20250514"
      }

      assert {:ok, %{session: session}} = Sessions.register_from_hook(params, nil)
      assert session.model == "claude-sonnet-4-20250514"
      assert session.model_name != nil
    end

    test "creates session without model info when model string is nil" do
      uuid = Ecto.UUID.generate()

      params = %{
        "session_id" => uuid,
        "description" => "test"
      }

      assert {:ok, %{session: session}} = Sessions.register_from_hook(params, nil)
      assert is_nil(session.model_name)
    end

    test "sets project_id on both agent and session" do
      uuid = Ecto.UUID.generate()
      # Use a real project or nil — just verify passthrough
      params = %{"session_id" => uuid, "description" => "test"}

      assert {:ok, %{session: session}} = Sessions.register_from_hook(params, 1)
      assert session.project_id == 1
    end

    test "reuses existing agent with same uuid" do
      agent_uuid = Ecto.UUID.generate()
      _agent = create_agent(%{uuid: agent_uuid})

      params = %{
        "session_id" => Ecto.UUID.generate(),
        "agent_id" => agent_uuid,
        "description" => "test"
      }

      assert {:ok, %{agent: agent}} = Sessions.register_from_hook(params, nil)
      assert agent.uuid == agent_uuid
    end

    test "returns tagged :session error on duplicate session uuid" do
      uuid = Ecto.UUID.generate()
      params = %{"session_id" => uuid, "description" => "test"}

      assert {:ok, _} = Sessions.register_from_hook(params, nil)
      assert {:error, :session, changeset} = Sessions.register_from_hook(params, nil)
      assert changeset.valid? == false
    end

    test "passes entrypoint and worktree_path through to session" do
      uuid = Ecto.UUID.generate()

      params = %{
        "session_id" => uuid,
        "description" => "test",
        "entrypoint" => "sdk-cli",
        "worktree_path" => "/tmp/test-worktree"
      }

      assert {:ok, %{session: session}} = Sessions.register_from_hook(params, nil)
      assert session.entrypoint == "sdk-cli"
      assert session.git_worktree_path == "/tmp/test-worktree"
    end
  end

  # ---------------------------------------------------------------------------
  # get_session_counts/1
  # ---------------------------------------------------------------------------

  describe "get_session_counts/1" do
    test "returns zero counts for session with no associated records" do
      session = new_session()
      counts = Sessions.get_session_counts(session.id)

      assert counts == %{tasks: 0, commits: 0, logs: 0, notes: 0, messages: 0}
    end

    test "counts tasks linked via task_sessions join table" do
      session = new_session()
      task = create_task()
      Tasks.link_session_to_task(task.id, session.id)

      counts = Sessions.get_session_counts(session.id)
      assert counts.tasks == 1
    end

    test "counts commits for the session" do
      session = new_session()

      {:ok, _} =
        Commits.create_commit(%{
          session_id: session.id,
          commit_hash: "abc#{System.unique_integer([:positive])}"
        })

      counts = Sessions.get_session_counts(session.id)
      assert counts.commits == 1
    end

    test "counts session logs" do
      session = new_session()

      {:ok, _} =
        Logs.create_session_log(%{
          session_id: session.id,
          level: "info",
          category: "test",
          message: "test log"
        })

      counts = Sessions.get_session_counts(session.id)
      assert counts.logs == 1
    end

    test "counts notes with parent_type 'session'" do
      session = new_session()

      {:ok, _} =
        Notes.create_note(%{
          parent_type: "session",
          parent_id: to_string(session.id),
          body: "a note"
        })

      counts = Sessions.get_session_counts(session.id)
      assert counts.notes == 1
    end

    test "parent_type 'sessions' is rejected by Note changeset — legacy DB rows only" do
      # The Note schema validates parent_type against a strict allowlist that
      # includes "session" but not "sessions". The dual-value check in
      # get_session_counts is forward-compatible with old rows but no new
      # notes can be created with the legacy type.
      assert {:error, changeset} =
               Notes.create_note(%{
                 parent_type: "sessions",
                 parent_id: "1",
                 body: "legacy note"
               })

      assert {"is invalid", _} = changeset.errors[:parent_type]
    end

    test "counts messages linked to session" do
      session = new_session()

      {:ok, _} =
        Messages.create_message(%{
          session_id: session.id,
          body: "hello",
          sender_role: "user",
          direction: "inbound"
        })

      counts = Sessions.get_session_counts(session.id)
      assert counts.messages == 1
    end

    test "counts are independent per session" do
      s1 = new_session()
      s2 = new_session()

      task = create_task()
      Tasks.link_session_to_task(task.id, s1.id)

      counts_s1 = Sessions.get_session_counts(s1.id)
      counts_s2 = Sessions.get_session_counts(s2.id)

      assert counts_s1.tasks == 1
      assert counts_s2.tasks == 0
    end

    test "multiple records of each type are counted correctly" do
      session = new_session()

      for _ <- 1..3 do
        t = create_task()
        Tasks.link_session_to_task(t.id, session.id)
      end

      for i <- 1..2 do
        Commits.create_commit(%{session_id: session.id, commit_hash: "hash#{i}_#{System.unique_integer([:positive])}"})
      end

      counts = Sessions.get_session_counts(session.id)
      assert counts.tasks == 3
      assert counts.commits == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Sessions.Queries.list_sessions_filtered/1
  # ---------------------------------------------------------------------------

  describe "Queries.list_sessions_filtered/1 — status filters" do
    test "status 'active' returns only non-ended sessions (excludes discovered agents)" do
      agent = create_agent(%{status: "working"})
      active_session = create_session(agent, %{status: "working"})
      _ended_session = create_session(agent, %{status: "completed", ended_at: DateTime.utc_now()})

      results = Queries.list_sessions_filtered(status_filter: "active")
      ids = Enum.map(results, & &1.id)

      assert active_session.id in ids
    end

    test "status 'active' excludes sessions whose agent has status 'discovered'" do
      discovered_agent = create_agent(%{status: "discovered"})
      _discovered_session = create_session(discovered_agent, %{status: "working"})

      working_agent = create_agent(%{status: "working"})
      working_session = create_session(working_agent, %{status: "working"})

      results = Queries.list_sessions_filtered(status_filter: "active")
      ids = Enum.map(results, & &1.id)

      assert working_session.id in ids
      refute _discovered_session.id in ids
    end

    test "status 'completed' returns only sessions with ended_at set" do
      agent = create_agent()
      ended = create_session(agent, %{status: "completed", ended_at: DateTime.utc_now()})
      active = create_session(agent, %{status: "working"})

      results = Queries.list_sessions_filtered(status_filter: "completed")
      ids = Enum.map(results, & &1.id)

      assert ended.id in ids
      refute active.id in ids
    end

    test "status 'stale' returns only non-ended sessions with stale agent" do
      stale_agent = create_agent(%{status: "stale"})
      stale_session = create_session(stale_agent, %{status: "working"})

      working_agent = create_agent(%{status: "working"})
      _other_session = create_session(working_agent, %{status: "working"})

      results = Queries.list_sessions_filtered(status_filter: "stale")
      ids = Enum.map(results, & &1.id)

      assert stale_session.id in ids
      refute _other_session.id in ids
    end

    test "status 'discovered' returns sessions whose agent is discovered" do
      disc_agent = create_agent(%{status: "discovered"})
      disc_session = create_session(disc_agent)

      normal_agent = create_agent(%{status: "working"})
      _normal_session = create_session(normal_agent)

      results = Queries.list_sessions_filtered(status_filter: "discovered")
      ids = Enum.map(results, & &1.id)

      assert disc_session.id in ids
      refute _normal_session.id in ids
    end

    test "status 'all' returns both active and ended sessions" do
      agent = create_agent()
      active = create_session(agent, %{status: "working"})
      ended = create_session(agent, %{status: "completed", ended_at: DateTime.utc_now()})

      results = Queries.list_sessions_filtered(status_filter: "all")
      ids = Enum.map(results, & &1.id)

      assert active.id in ids
      assert ended.id in ids
    end

    test "unknown status value returns all sessions (falls through to catch-all)" do
      agent = create_agent()
      session = create_session(agent)

      results = Queries.list_sessions_filtered(status_filter: "nonexistent")
      ids = Enum.map(results, & &1.id)

      assert session.id in ids
    end
  end

  describe "Queries.list_sessions_filtered/1 — search" do
    test "empty search_query returns results without FTS filter" do
      agent = create_agent()
      session = create_session(agent, %{name: "findable session"})

      results = Queries.list_sessions_filtered(search_query: "", status_filter: "all")
      ids = Enum.map(results, & &1.id)

      assert session.id in ids
    end

    test "short query (< 3 chars) would still be applied — filtering is caller's responsibility" do
      agent = create_agent()
      _session = create_session(agent)

      # The context doesn't enforce min length — that's the LiveView's job
      results = Queries.list_sessions_filtered(search_query: "ab", status_filter: "all")
      assert is_list(results)
    end
  end

  describe "Queries.list_sessions_filtered/1 — limit and offset" do
    test "limit caps result count" do
      agent = create_agent()
      for _ <- 1..5, do: create_session(agent)

      results = Queries.list_sessions_filtered(status_filter: "all", limit: 2)
      assert length(results) <= 2
    end

    test "offset skips records" do
      agent = create_agent()
      for _ <- 1..4, do: create_session(agent)

      all_results = Queries.list_sessions_filtered(status_filter: "all", limit: 10, offset: 0)
      offset_results = Queries.list_sessions_filtered(status_filter: "all", limit: 10, offset: 2)

      assert length(offset_results) < length(all_results)
    end
  end

  # ---------------------------------------------------------------------------
  # Sessions.Queries.get_session_overview_row/1
  # ---------------------------------------------------------------------------

  describe "Queries.get_session_overview_row/1" do
    test "returns {:ok, row} with expected shape for existing session" do
      agent = create_agent()
      session = create_session(agent)

      assert {:ok, row} = Queries.get_session_overview_row(session.id)

      assert row.id == session.id
      assert row.uuid == session.uuid
      assert row.agent_id == agent.id
      assert row.agent_uuid == agent.uuid
      assert Map.has_key?(row, :status)
      assert Map.has_key?(row, :started_at)
      assert Map.has_key?(row, :ended_at)
      assert Map.has_key?(row, :current_task_title)
    end

    test "returns {:error, :not_found} for non-existent session" do
      assert {:error, :not_found} = Queries.get_session_overview_row(0)
    end

    test "returns {:error, :not_found} for archived session" do
      agent = create_agent()
      session = create_session(agent)
      Sessions.archive_session(session)

      assert {:error, :not_found} = Queries.get_session_overview_row(session.id)
    end

    test "current_task_title is nil when session has no in-progress task" do
      agent = create_agent()
      session = create_session(agent)

      {:ok, row} = Queries.get_session_overview_row(session.id)
      assert is_nil(row.current_task_title)
    end

    test "current_task_title reflects the linked in-progress task title" do
      agent = create_agent()
      session = create_session(agent)
      task = in_progress_task(%{title: "doing important work"})
      Tasks.link_session_to_task(task.id, session.id)

      {:ok, row} = Queries.get_session_overview_row(session.id)
      assert row.current_task_title == "doing important work"
    end

    test "current_task_title is nil when linked task is not in-progress" do
      agent = create_agent()
      session = create_session(agent)
      task = create_task(%{title: "todo task", state_id: 1})
      Tasks.link_session_to_task(task.id, session.id)

      {:ok, row} = Queries.get_session_overview_row(session.id)
      assert is_nil(row.current_task_title)
    end
  end

  # ---------------------------------------------------------------------------
  # Sessions.Queries.list_session_overview_rows/1
  # ---------------------------------------------------------------------------

  describe "Queries.list_session_overview_rows/1" do
    test "returns rows with expected shape" do
      agent = create_agent()
      _session = create_session(agent)

      rows = Queries.list_session_overview_rows(limit: 10)

      assert is_list(rows)
      assert rows != []

      row = hd(rows)
      assert Map.has_key?(row, :id)
      assert Map.has_key?(row, :uuid)
      assert Map.has_key?(row, :agent_id)
      assert Map.has_key?(row, :current_task_title)
      assert Map.has_key?(row, :model_name)
    end

    test "excludes archived sessions by default" do
      agent = create_agent()
      session = create_session(agent)
      Sessions.archive_session(session)

      rows = Queries.list_session_overview_rows(limit: 100)
      ids = Enum.map(rows, & &1.id)

      refute session.id in ids
    end

    test "includes archived sessions when include_archived: true" do
      agent = create_agent()
      session = create_session(agent)
      Sessions.archive_session(session)

      rows = Queries.list_session_overview_rows(limit: 100, include_archived: true)
      ids = Enum.map(rows, & &1.id)

      assert session.id in ids
    end

    test "limit is respected" do
      agent = create_agent()
      for _ <- 1..5, do: create_session(agent)

      rows = Queries.list_session_overview_rows(limit: 2)
      assert length(rows) <= 2
    end
  end

  # ---------------------------------------------------------------------------
  # Sessions.Queries.count_session_overview_rows/1
  # ---------------------------------------------------------------------------

  describe "Queries.count_session_overview_rows/1" do
    test "returns integer count" do
      agent = create_agent()
      create_session(agent)

      count = Queries.count_session_overview_rows()
      assert is_integer(count)
      assert count > 0
    end

    test "excludes archived sessions from count" do
      agent = create_agent()
      session = create_session(agent)
      before_count = Queries.count_session_overview_rows()

      Sessions.archive_session(session)
      after_count = Queries.count_session_overview_rows()

      assert after_count == before_count - 1
    end
  end

  # ---------------------------------------------------------------------------
  # Sessions.Queries — delegate passthrough from Sessions module
  # ---------------------------------------------------------------------------

  describe "Sessions context delegates to Queries" do
    test "Sessions.list_sessions_filtered/1 is callable and returns list" do
      agent = create_agent()
      _session = create_session(agent)

      results = Sessions.list_sessions_filtered(status_filter: "all", limit: 10)
      assert is_list(results)
    end

    test "Sessions.list_session_overview_rows/1 is callable and returns list" do
      results = Sessions.list_session_overview_rows(limit: 5)
      assert is_list(results)
    end

    test "Sessions.get_session_overview_row/1 is callable" do
      assert {:error, :not_found} = Sessions.get_session_overview_row(0)
    end

    test "Sessions.count_session_overview_rows/1 is callable and returns integer" do
      assert is_integer(Sessions.count_session_overview_rows())
    end
  end

  # ---------------------------------------------------------------------------
  # message body FTS via list_sessions_filtered
  # ---------------------------------------------------------------------------

  describe "list_sessions_filtered message body FTS" do
    defp create_message(session_id, body, role \\ "agent") do
      {:ok, msg} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          session_id: session_id,
          sender_role: role,
          recipient_role: "user",
          direction: "inbound",
          body: body,
          status: "delivered",
          provider: "test"
        })

      msg
    end

    test "surfaces session matched only by message body, not name/description" do
      agent = create_agent()
      session = create_session(agent, %{name: "generic-name", description: "generic-desc"})
      create_message(session.id, "the phosphorescent jellyfish swam slowly")

      results =
        Sessions.list_sessions_filtered(
          search_query: "phosphorescent",
          status_filter: "all",
          limit: 10
        )

      ids = Enum.map(results, & &1.id)
      assert session.id in ids
    end

    test "does not surface session with tool-role message matching the term" do
      agent = create_agent()
      session = create_session(agent, %{name: "generic-name-2"})
      create_message(session.id, "phosphorescent tool output", "tool")

      results =
        Sessions.list_sessions_filtered(
          search_query: "phosphorescent",
          status_filter: "all",
          limit: 10
        )

      ids = Enum.map(results, & &1.id)
      refute session.id in ids
    end

    test "includes session matched by assistant role message" do
      agent = create_agent()
      session = create_session(agent, %{name: "generic-name-3"})
      create_message(session.id, "the phosphorescent jellyfish appeared", "assistant")

      results =
        Sessions.list_sessions_filtered(
          search_query: "phosphorescent",
          status_filter: "all",
          limit: 10
        )

      ids = Enum.map(results, & &1.id)
      assert session.id in ids
    end

    test "returns no results for term not in any message or session field" do
      results =
        Sessions.list_sessions_filtered(
          search_query: "xyzzyuniquetermnotindata",
          status_filter: "all",
          limit: 10
        )

      assert results == []
    end
  end
end
