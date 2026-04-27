defmodule EyeInTheSky.Scheduler.AgentStatusTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Scheduler.AgentStatus
  alias EyeInTheSky.Sessions

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_agent(overrides) do
    {:ok, agent} =
      Agents.create_agent(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            description: "Test agent",
            source: "test",
            status: "working"
          },
          overrides
        )
      )

    agent
  end

  defp iso8601_hours_ago(hours) do
    DateTime.utc_now()
    |> DateTime.add(-hours * 3600, :second)
    |> DateTime.to_iso8601()
  end

  # ---------------------------------------------------------------------------
  # Scheduler smoke test — doesn't crash with ISO8601 string inputs
  # ---------------------------------------------------------------------------

  describe "AgentStatus scheduler" do
    test "processes agents with nil last_activity_at without crashing" do
      create_agent(%{last_activity_at: nil})

      # Start a one-off scheduler and trigger mark_stale immediately
      {:ok, pid} = GenServer.start(AgentStatus, nil)
      send(pid, :mark_stale)

      # Give it time to process
      Process.sleep(100)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "processes agents with a recent ISO8601 last_activity_at without crashing" do
      create_agent(%{last_activity_at: iso8601_hours_ago(1)})

      {:ok, pid} = GenServer.start(AgentStatus, nil)
      send(pid, :mark_stale)

      Process.sleep(100)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "processes agents with an old ISO8601 last_activity_at without crashing" do
      # 25 hours ago — should trigger is_too_old
      create_agent(%{last_activity_at: iso8601_hours_ago(25)})

      {:ok, pid} = GenServer.start(AgentStatus, nil)
      send(pid, :mark_stale)

      Process.sleep(100)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "processes agents with a stale ISO8601 last_activity_at without crashing" do
      # 2 hours ago — should trigger is_stale
      create_agent(%{last_activity_at: iso8601_hours_ago(2)})

      {:ok, pid} = GenServer.start(AgentStatus, nil)
      send(pid, :mark_stale)

      Process.sleep(100)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "handles mixed agents — some nil, some ISO8601 — without crashing" do
      create_agent(%{last_activity_at: nil})
      create_agent(%{last_activity_at: iso8601_hours_ago(2)})
      create_agent(%{last_activity_at: iso8601_hours_ago(25)})
      create_agent(%{last_activity_at: iso8601_hours_ago(0)})

      {:ok, pid} = GenServer.start(AgentStatus, nil)
      send(pid, :mark_stale)

      Process.sleep(100)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "sweep_zombie_sessions also updates linked agent status to failed" do
      # Create an agent and session
      {:ok, agent} =
        Agents.create_agent(%{
          uuid: Ecto.UUID.generate(),
          description: "Test agent",
          source: "test",
          status: "working"
        })

      cutoff = DateTime.utc_now() |> DateTime.add(-31 * 60, :second)

      {:ok, session} =
        Sessions.create_session(%{
          agent_id: agent.id,
          status: "working",
          started_at: cutoff,
          last_activity_at: cutoff,
          provider: "claude"
        })

      # Call the sweep
      AgentStatus.sweep_zombie_sessions_for_testing()

      # Assert both session and agent are now failed
      updated_session = Sessions.get_session!(session.id)
      assert updated_session.status == "failed"
      assert updated_session.status_reason == "zombie_swept"

      {:ok, updated_agent} = Agents.get_agent(agent.id)
      assert updated_agent.status == "failed"
    end

    test "sweep_zombie_sessions marks stuck working sessions as failed" do
      # Create an agent first (required for session)
      {:ok, agent} =
        Agents.create_agent(%{
          uuid: Ecto.UUID.generate(),
          description: "Test agent",
          source: "test",
          status: "working"
        })

      # Create a session with status working and last_activity_at > 30 min ago
      cutoff = DateTime.utc_now() |> DateTime.add(-31 * 60, :second)

      {:ok, session} =
        Sessions.create_session(%{
          agent_id: agent.id,
          status: "working",
          started_at: cutoff,
          last_activity_at: cutoff,
          provider: "claude"
        })

      # Call the sweep
      AgentStatus.sweep_zombie_sessions_for_testing()

      # Assert status is now failed
      updated = Sessions.get_session!(session.id)
      assert updated.status == "failed"
      assert updated.status_reason == "zombie_swept"
    end

    test "sweep_zombie_sessions does NOT sweep fresh session with NULL last_activity_at" do
      {:ok, agent} =
        Agents.create_agent(%{
          uuid: Ecto.UUID.generate(),
          description: "Test agent",
          source: "test",
          status: "working"
        })

      # Fresh session: started now, never had activity yet
      {:ok, session} =
        Sessions.create_session(%{
          agent_id: agent.id,
          status: "working",
          started_at: DateTime.utc_now(),
          last_activity_at: nil,
          provider: "claude"
        })

      AgentStatus.sweep_zombie_sessions_for_testing()

      updated = Sessions.get_session!(session.id)
      assert updated.status == "working"
      refute updated.status_reason == "zombie_swept"
    end

    test "sweep_zombie_sessions DOES sweep old session with NULL last_activity_at when started_at is stale" do
      {:ok, agent} =
        Agents.create_agent(%{
          uuid: Ecto.UUID.generate(),
          description: "Test agent",
          source: "test",
          status: "working"
        })

      stale = DateTime.utc_now() |> DateTime.add(-31 * 60, :second)

      {:ok, session} =
        Sessions.create_session(%{
          agent_id: agent.id,
          status: "working",
          started_at: stale,
          last_activity_at: nil,
          provider: "claude"
        })

      AgentStatus.sweep_zombie_sessions_for_testing()

      updated = Sessions.get_session!(session.id)
      assert updated.status == "failed"
      assert updated.status_reason == "zombie_swept"
    end
  end
end
