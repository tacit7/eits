defmodule EyeInTheSky.OrchestratorTimersTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias EyeInTheSky.OrchestratorTimers.Server

  setup do
    # Start a fresh unnamed server per test to avoid state leaking between tests.
    name = :"timer_test_#{System.unique_integer([:positive])}"
    pid = start_supervised!({Server, name: name})
    {:ok, server: pid}
  end

  describe "schedule_once/3" do
    test "creates timer state with mode :once", %{server: pid} do
      assert {:ok, :scheduled} = GenServer.call(pid, {:schedule_once, 999, 60_000, "hello"})
      record = GenServer.call(pid, {:get_timer, 999})
      assert record.mode == :once
      assert record.interval_ms == 60_000
      assert record.message == "hello"
      assert %DateTime{} = record.started_at
      assert %DateTime{} = record.next_fire_at
      assert is_reference(record.token)
    end
  end

  describe "schedule_repeating/3" do
    test "creates timer state with mode :repeating", %{server: pid} do
      assert {:ok, :scheduled} = GenServer.call(pid, {:schedule_repeating, 999, 30_000, "ping"})
      record = GenServer.call(pid, {:get_timer, 999})
      assert record.mode == :repeating
      assert record.interval_ms == 30_000
      assert record.message == "ping"
    end
  end

  describe "replace-on-reschedule" do
    test "returns :replaced and installs new timer when one already active", %{server: pid} do
      assert {:ok, :scheduled} = GenServer.call(pid, {:schedule_once, 999, 60_000, "first"})
      assert {:ok, :replaced} = GenServer.call(pid, {:schedule_once, 999, 90_000, "second"})
      record = GenServer.call(pid, {:get_timer, 999})
      assert record.message == "second"
      assert record.interval_ms == 90_000
    end
  end

  describe "cancel/1" do
    test "removes the timer from state", %{server: pid} do
      GenServer.call(pid, {:schedule_once, 999, 60_000, "test"})
      assert :ok = GenServer.call(pid, {:cancel, 999})
      assert nil == GenServer.call(pid, {:get_timer, 999})
    end

    test "is a no-op when no timer active", %{server: pid} do
      assert :ok = GenServer.call(pid, {:cancel, 999})
    end
  end

  describe "get_timer/1" do
    test "returns nil when no timer active for session", %{server: pid} do
      assert nil == GenServer.call(pid, {:get_timer, 12_345})
    end
  end

  describe "stale token" do
    test "stale timer message is ignored — state unchanged after replacement", %{server: pid} do
      # Schedule and immediately replace. The first timer's message may still be
      # in the mailbox when we replace. It must be ignored.
      GenServer.call(pid, {:schedule_once, 999, 5, "first"})
      GenServer.call(pid, {:schedule_once, 999, 60_000, "second"})
      # Give time for the stale first timer to arrive and be processed
      Process.sleep(50)
      # Second timer must still be active
      record = GenServer.call(pid, {:get_timer, 999})
      assert record != nil
      assert record.message == "second"
    end
  end

  describe "one-shot fire behavior" do
    test "removes itself from state after firing", %{server: pid} do
      GenServer.call(pid, {:schedule_once, 999, 10, "test"})
      Process.sleep(100)
      assert nil == GenServer.call(pid, {:get_timer, 999})
    end
  end

  describe "repeating fire behavior" do
    test "reschedules itself after firing", %{server: pid} do
      GenServer.call(pid, {:schedule_repeating, 999, 10, "test"})
      Process.sleep(50)
      record = GenServer.call(pid, {:get_timer, 999})
      assert record != nil
      assert record.mode == :repeating
    end
  end

  describe "delivery failure policy" do
    test "one-shot removes itself even when delivery fails (no worker for session)", %{server: pid} do
      # session_id 99999 has no AgentWorker — send_message returns error
      GenServer.call(pid, {:schedule_once, 99_999, 10, "test"})
      Process.sleep(100)
      assert nil == GenServer.call(pid, {:get_timer, 99_999})
    end

    test "repeating reschedules even when delivery fails (no worker for session)", %{server: pid} do
      GenServer.call(pid, {:schedule_repeating, 99_999, 10, "test"})
      Process.sleep(50)
      record = GenServer.call(pid, {:get_timer, 99_999})
      assert record != nil
      assert record.mode == :repeating
    end
  end
end
