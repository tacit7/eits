# credo:disable-for-this-file Credo.Check.Warning.UnsafeToAtom
defmodule EyeInTheSky.Claude.AgentWorker.EvictionTest do
  @moduledoc """
  Covers the eviction snapshot contract used by SessionBridge to reclaim an
  AgentSupervisor slot when the supervisor is at capacity. The safety property
  is: a worker is only ever reported "parked" (evictable) when it is idle with
  an empty queue — never while it has in-flight or queued work.
  """
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias EyeInTheSky.Claude.{AgentRegistry, AgentSupervisor, AgentWorker}

  describe "handle_call(:eviction_snapshot, ...)" do
    test "idle with empty queue is parked and reports idle_since" do
      since = DateTime.utc_now()
      state = %AgentWorker{status: :idle, queue: [], idle_since: since}

      assert {:reply, {true, ^since}, ^state} =
               AgentWorker.handle_call(:eviction_snapshot, self(), state)
    end

    test "idle but with a queued message is NOT parked" do
      state = %AgentWorker{status: :idle, queue: [:queued_job], idle_since: DateTime.utc_now()}

      assert {:reply, {false, _since}, ^state} =
               AgentWorker.handle_call(:eviction_snapshot, self(), state)
    end

    test "running worker is NOT parked even with an empty queue" do
      state = %AgentWorker{status: :running, queue: [], idle_since: DateTime.utc_now()}

      assert {:reply, {false, _since}, ^state} =
               AgentWorker.handle_call(:eviction_snapshot, self(), state)
    end

    test "retry_wait worker is NOT parked" do
      state = %AgentWorker{status: :retry_wait, queue: [], idle_since: DateTime.utc_now()}

      assert {:reply, {false, _since}, ^state} =
               AgentWorker.handle_call(:eviction_snapshot, self(), state)
    end
  end

  describe "eviction_snapshot/1 (live worker)" do
    test "a freshly started idle worker reports parked with a real timestamp" do
      session_id = System.unique_integer([:positive])

      opts = [
        session_id: session_id,
        provider_conversation_id: Ecto.UUID.generate(),
        eits_session_uuid: Ecto.UUID.generate(),
        agent_id: System.unique_integer([:positive]),
        project_path: File.cwd!(),
        provider: "claude"
      ]

      {:ok, pid} = DynamicSupervisor.start_child(AgentSupervisor, {AgentWorker, opts})
      on_exit(fn -> DynamicSupervisor.terminate_child(AgentSupervisor, pid) end)

      assert [{^pid, "claude"}] = Registry.lookup(AgentRegistry, {:session, session_id})
      assert {true, %DateTime{}} = AgentWorker.eviction_snapshot(pid)
    end

    test "a dead pid reports not-parked instead of crashing the caller" do
      {:ok, pid} = Agent.start(fn -> :ok end)
      Agent.stop(pid)
      refute Process.alive?(pid)

      assert {false, nil} = AgentWorker.eviction_snapshot(pid)
    end
  end
end
