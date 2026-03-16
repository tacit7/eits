defmodule EyeInTheSkyWeb.Scheduler.AgentStatusTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.Agents
  alias EyeInTheSkyWeb.Scheduler.AgentStatus

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_agent(overrides \\ %{}) do
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
  end
end
