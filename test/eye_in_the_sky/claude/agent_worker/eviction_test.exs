# credo:disable-for-this-file Credo.Check.Warning.UnsafeToAtom
defmodule EyeInTheSky.Claude.AgentWorker.EvictionTest do
  @moduledoc """
  Covers the eviction contract used by SessionBridge to reclaim an AgentSupervisor
  slot at capacity. Safety property: a worker is only ever evicted when it holds
  no in-flight or queued work — and the kill is atomic (`evict_if_parked` re-checks
  inside the worker's own message loop), so a worker that starts work between the
  advisory snapshot and the kill is skipped, never terminated mid-job.
  """
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias EyeInTheSky.Claude.{AgentRegistry, AgentSupervisor, AgentWorker}

  describe "eviction_snapshot predicate (advisory ranking)" do
    test "idle with empty queue is evictable and reports idle_since" do
      since = DateTime.utc_now()
      state = %AgentWorker{status: :idle, queue: [], idle_since: since}

      assert {:reply, {true, ^since}, ^state} =
               AgentWorker.handle_call(:eviction_snapshot, self(), state)
    end

    test "failed with empty queue is evictable (no work, no idle timer — eviction is its only reclaim)" do
      since = DateTime.utc_now()
      state = %AgentWorker{status: :failed, queue: [], idle_since: since}

      assert {:reply, {true, ^since}, ^state} =
               AgentWorker.handle_call(:eviction_snapshot, self(), state)
    end

    test "idle but with a queued message is NOT evictable" do
      state = %AgentWorker{status: :idle, queue: [:queued_job], idle_since: DateTime.utc_now()}
      assert {:reply, {false, _}, ^state} = AgentWorker.handle_call(:eviction_snapshot, self(), state)
    end

    test "failed but with a queued message is NOT evictable" do
      state = %AgentWorker{status: :failed, queue: [:queued_job], idle_since: DateTime.utc_now()}
      assert {:reply, {false, _}, ^state} = AgentWorker.handle_call(:eviction_snapshot, self(), state)
    end

    test "running worker is NOT evictable even with an empty queue" do
      state = %AgentWorker{status: :running, queue: [], idle_since: DateTime.utc_now()}
      assert {:reply, {false, _}, ^state} = AgentWorker.handle_call(:eviction_snapshot, self(), state)
    end

    test "retry_wait worker is NOT evictable" do
      state = %AgentWorker{status: :retry_wait, queue: [], idle_since: DateTime.utc_now()}
      assert {:reply, {false, _}, ^state} = AgentWorker.handle_call(:eviction_snapshot, self(), state)
    end
  end

  describe "evict_if_parked (atomic kill)" do
    test "parked worker self-stops with :normal (not restarted) and replies :ok" do
      state = %AgentWorker{status: :idle, queue: [], idle_since: DateTime.utc_now()}
      assert {:stop, :normal, :ok, ^state} = AgentWorker.handle_call(:evict_if_parked, self(), state)
    end

    test "failed+empty worker self-stops too" do
      state = %AgentWorker{status: :failed, queue: [], idle_since: DateTime.utc_now()}
      assert {:stop, :normal, :ok, ^state} = AgentWorker.handle_call(:evict_if_parked, self(), state)
    end

    test "a worker that has started work replies :busy and keeps running" do
      running = %AgentWorker{status: :running, queue: [], idle_since: DateTime.utc_now()}
      assert {:reply, :busy, ^running} = AgentWorker.handle_call(:evict_if_parked, self(), running)

      queued = %AgentWorker{status: :idle, queue: [:job], idle_since: DateTime.utc_now()}
      assert {:reply, :busy, ^queued} = AgentWorker.handle_call(:evict_if_parked, self(), queued)
    end
  end

  describe "live worker" do
    test "a freshly started idle worker is evictable, then evict_if_parked terminates it" do
      session_id = System.unique_integer([:positive])
      {:ok, pid} = start_idle_worker(session_id)

      assert [{^pid, "claude"}] = Registry.lookup(AgentRegistry, {:session, session_id})
      assert {true, %DateTime{}} = AgentWorker.eviction_snapshot(pid)

      ref = Process.monitor(pid)
      assert :ok = AgentWorker.evict_if_parked(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
      refute Process.alive?(pid)
      # transient + :normal exit ⇒ not restarted ⇒ deregistered
      assert [] = Registry.lookup(AgentRegistry, {:session, session_id})
    end

    test "a dead pid reports not-evictable / busy instead of crashing the caller" do
      {:ok, pid} = Agent.start(fn -> :ok end)
      Agent.stop(pid)
      refute Process.alive?(pid)

      assert {false, nil} = AgentWorker.eviction_snapshot(pid)
      assert :busy = AgentWorker.evict_if_parked(pid)
    end
  end

  defp start_idle_worker(session_id) do
    opts = [
      session_id: session_id,
      provider_conversation_id: Ecto.UUID.generate(),
      eits_session_uuid: Ecto.UUID.generate(),
      agent_id: System.unique_integer([:positive]),
      project_path: File.cwd!(),
      provider: "claude"
    ]

    result = DynamicSupervisor.start_child(AgentSupervisor, {AgentWorker, opts})

    case result do
      {:ok, pid} -> on_exit(fn -> safe_terminate(pid) end)
      _ -> :ok
    end

    result
  end

  defp safe_terminate(pid) do
    if Process.alive?(pid), do: DynamicSupervisor.terminate_child(AgentSupervisor, pid)
  end
end
