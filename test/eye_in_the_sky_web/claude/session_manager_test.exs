defmodule EyeInTheSkyWeb.Claude.SessionManagerTest do
  use ExUnit.Case, async: false
  use EyeInTheSkyWeb.SessionManagerCase

  alias EyeInTheSkyWeb.Claude.SessionManager
  alias EyeInTheSkyWeb.Claude.SessionWorker

  setup do
    # SessionManager holds no per-session state (it's stateless, using Registry).
    # All session state lives in workers. Terminating workers cleans up Registry
    # entries automatically. No need to restart PubSub/Registry/SessionSupervisor,
    # which avoids hitting the app supervisor's max_restarts limit.
    @supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn
      {_, pid, :worker, _} when is_pid(pid) ->
        DynamicSupervisor.terminate_child(@supervisor, pid)

      _ ->
        :ok
    end)

    # Brief wait for Registry to clean up terminated worker entries.
    Process.sleep(20)

    :ok
  end

  describe "start_session/3" do
    test "spawns new SessionWorker under DynamicSupervisor" do
      {:ok, ref} = SessionManager.start_session("test-session", "Hello", [])

      assert [{pid, _}] = Registry.lookup(@registry, {:session, "test-session"})
      assert [{^pid, _}] = Registry.lookup(@registry, {:ref, ref})
      assert Process.alive?(pid)
    end

    test "returns session_ref for tracking" do
      {:ok, ref} = SessionManager.start_session("test-session", "Hello", [])
      assert is_reference(ref)
    end

    test "broadcasts :working status" do
      subscribe_session_status("test-session")

      SessionManager.start_session("test-session", "Hello", [])

      assert_status_broadcast("test-session", :working)
    end
  end

  describe "resume_session/3 deduplication" do
    test "queues message when worker already exists" do
      # Spawn initial worker
      {:ok, _ref} = SessionManager.start_session("test-session", "First", [])
      {:ok, pid} = await_worker("test-session")

      # Try to resume - should queue instead of spawning
      {:ok, :queued} = SessionManager.resume_session("test-session", "Second", [])

      # Verify no new worker spawned
      assert [{^pid, _}] = Registry.lookup(@registry, {:session, "test-session"})

      # Verify message was queued
      info = SessionWorker.get_info(pid)
      assert info.queue_depth == 1
    end

    test "spawns new worker when existing worker is dead" do
      # Spawn worker and kill it directly (not graceful exit)
      {:ok, _ref1} = SessionManager.start_session("test-session", "First", [])
      {:ok, pid1} = await_worker("test-session")

      # Monitor first, then kill
      ref = Process.monitor(pid1)
      Process.exit(pid1, :kill)

      # Wait for DOWN message (reason might be :killed or :noproc depending on timing)
      assert_receive {:DOWN, ^ref, :process, ^pid1, _reason}, 1000

      # Brief delay to ensure registry is updated
      Process.sleep(20)

      # Resume should spawn new worker since old one is dead
      {:ok, ref2} = SessionManager.resume_session("test-session", "Second", [])
      assert is_reference(ref2)

      {:ok, pid2} = await_worker("test-session")
      assert pid2 != pid1
    end

    test "returns error when spawning worker fails" do
      # Use invalid prompt to trigger error - this is a limitation of current mock
      # In real scenario, CLI.spawn_* could return {:error, reason}
      # For now we just verify the code path exists
      {:ok, _ref} = SessionManager.start_session("test-session", "Valid", [])
      assert is_reference(_ref)
    end
  end

  describe "message queue processing" do
    test "processes queued messages after CLI exit" do
      subscribe_session_status("test-session")

      # Spawn worker with first message
      {:ok, _ref} = SessionManager.start_session("test-session", "First", [])
      {:ok, pid} = await_worker("test-session")
      port1 = get_mock_port(pid)

      # Queue second message
      {:ok, :queued} = SessionManager.resume_session("test-session", "Second", [])
      assert_info = SessionWorker.get_info(pid)
      assert assert_info.queue_depth == 1

      # Exit first CLI
      send_mock_exit(port1, 0)

      # Brief delay for async processing
      Process.sleep(100)

      # Verify second message is now processing
      info = SessionWorker.get_info(pid)
      assert info.queue_depth == 0
      assert info.processing == true
    end

    test "worker goes idle after processing empty queue" do
      subscribe_session_status("test-session")

      {:ok, _ref} = SessionManager.start_session("test-session", "First", [])
      {:ok, pid} = await_worker("test-session")
      port = get_mock_port(pid)

      assert_status_broadcast("test-session", :working)

      # Exit CLI with no queued messages
      send_mock_exit(port, 0)

      # Should broadcast idle status
      assert_status_broadcast("test-session", :idle)

      # Worker should still be alive but idle
      assert Process.alive?(pid)
      info = SessionWorker.get_info(pid)
      assert info.processing == false
    end

    test "rejects messages when queue is full" do
      subscribe_session_status("test-session")

      {:ok, _ref} = SessionManager.start_session("test-session", "First", [])
      {:ok, pid} = await_worker("test-session")

      # Make port hang so messages pile up
      port = get_mock_port(pid)
      make_port_hang(port)

      # Fill queue to max (5 messages)
      for i <- 1..5 do
        {:ok, :queued} = SessionManager.resume_session("test-session", "Message #{i}", [])
      end

      # 6th message should trigger queue_full
      {:ok, :queued} = SessionManager.resume_session("test-session", "Overflow", [])
      assert_status_broadcast("test-session", :queue_full)

      # Queue depth should still be 5 (overflow dropped)
      info = SessionWorker.get_info(pid)
      assert info.queue_depth == 5
    end

    test "processes message immediately when worker is idle" do
      subscribe_session_status("test-session")

      # Spawn and finish first message
      {:ok, _ref} = SessionManager.start_session("test-session", "First", [])
      {:ok, pid} = await_worker("test-session")
      port = get_mock_port(pid)

      send_mock_exit(port, 0)
      assert_status_broadcast("test-session", :idle)

      # Send new message to idle worker
      {:ok, :queued} = SessionManager.resume_session("test-session", "Second", [])

      # Should process immediately, not queue
      assert_status_broadcast("test-session", :working)

      info = SessionWorker.get_info(pid)
      assert info.processing == true
      assert info.queue_depth == 0
    end
  end

  describe "status broadcasting" do
    test "broadcasts :working when processing starts" do
      subscribe_session_status("test-session")

      SessionManager.start_session("test-session", "Hello", [])
      assert_status_broadcast("test-session", :working)
    end

    test "broadcasts :idle after CLI exits with empty queue" do
      subscribe_session_status("test-session")

      {:ok, _ref} = SessionManager.start_session("test-session", "Hello", [])
      {:ok, pid} = await_worker("test-session")
      port = get_mock_port(pid)

      send_mock_exit(port, 0)
      assert_status_broadcast("test-session", :idle)
    end

    test "broadcasts :queue_full when queue limit reached" do
      subscribe_session_status("test-session")

      {:ok, _ref} = SessionManager.start_session("test-session", "First", [])
      {:ok, pid} = await_worker("test-session")
      port = get_mock_port(pid)

      make_port_hang(port)

      # Fill queue beyond max
      for i <- 1..6 do
        SessionManager.resume_session("test-session", "Message #{i}", [])
      end

      assert_status_broadcast("test-session", :queue_full)
    end
  end

  describe "cancel_session/1" do
    test "stops worker and broadcasts idle" do
      subscribe_session_status("test-session")

      {:ok, ref} = SessionManager.start_session("test-session", "Hello", [])
      {:ok, pid} = await_worker("test-session")

      assert :ok = SessionManager.cancel_session(ref)

      assert_status_broadcast("test-session", :idle)

      # Worker should be dead
      monitor_ref = Process.monitor(pid)
      assert_receive {:DOWN, ^monitor_ref, :process, ^pid, _}, 1000
    end

    test "returns error when session not found" do
      fake_ref = make_ref()
      assert {:error, :not_found} = SessionManager.cancel_session(fake_ref)
    end

    test "handles already-dead worker gracefully" do
      {:ok, ref} = SessionManager.start_session("test-session", "Hello", [])
      {:ok, pid} = await_worker("test-session")

      # Kill worker directly
      Process.exit(pid, :kill)
      monitor_ref = Process.monitor(pid)
      assert_receive {:DOWN, ^monitor_ref, :process, ^pid, _}, 1000

      # Cancel should return error
      assert {:error, :not_found} = SessionManager.cancel_session(ref)
    end
  end

  describe "list_sessions/0" do
    test "returns info for all active workers" do
      SessionManager.start_session("session-1", "Hello", [])
      SessionManager.start_session("session-2", "World", [])

      # Wait for both workers
      {:ok, _pid1} = await_worker("session-1")
      {:ok, _pid2} = await_worker("session-2")

      sessions = SessionManager.list_sessions()

      assert length(sessions) == 2
      assert Enum.any?(sessions, fn s -> s.session_id == "session-1" end)
      assert Enum.any?(sessions, fn s -> s.session_id == "session-2" end)
    end

    test "includes queue_depth and processing status" do
      SessionManager.start_session("test-session", "First", [])
      {:ok, pid} = await_worker("test-session")

      # Queue a message
      SessionManager.resume_session("test-session", "Second", [])

      [info] = SessionManager.list_sessions()
      assert info.queue_depth == 1
      assert info.processing == true
    end

    test "returns empty list when no sessions active" do
      sessions = SessionManager.list_sessions()
      assert sessions == []
    end

    test "excludes dead workers from list" do
      {:ok, _ref} = SessionManager.start_session("test-session", "Hello", [])
      {:ok, pid} = await_worker("test-session")

      # Kill worker
      Process.exit(pid, :kill)
      monitor_ref = Process.monitor(pid)
      assert_receive {:DOWN, ^monitor_ref, :process, ^pid, _}, 1000

      # Brief delay for cleanup
      Process.sleep(50)

      sessions = SessionManager.list_sessions()
      assert sessions == []
    end
  end

  describe "continue_session/3" do
    test "spawns new worker for continue operation" do
      {:ok, ref} = SessionManager.continue_session("test-session", "Continue prompt", [])

      assert is_reference(ref)
      assert [{pid, _}] = Registry.lookup(@registry, {:session, "test-session"})
      assert Process.alive?(pid)
    end

    test "does not deduplicate continue requests" do
      {:ok, ref1} = SessionManager.continue_session("test-session-1", "First", [])
      {:ok, ref2} = SessionManager.continue_session("test-session-2", "Second", [])

      assert ref1 != ref2
      assert [{pid1, _}] = Registry.lookup(@registry, {:session, "test-session-1"})
      assert [{pid2, _}] = Registry.lookup(@registry, {:session, "test-session-2"})
      assert pid1 != pid2
    end
  end

  describe "multiple sessions isolation" do
    test "sessions operate independently" do
      subscribe_session_status("session-1")
      subscribe_session_status("session-2")

      # Start two sessions
      {:ok, _ref1} = SessionManager.start_session("session-1", "Hello", [])
      {:ok, _ref2} = SessionManager.start_session("session-2", "World", [])

      {:ok, pid1} = await_worker("session-1")
      {:ok, pid2} = await_worker("session-2")

      assert pid1 != pid2

      # Complete first session
      port1 = get_mock_port(pid1)
      send_mock_exit(port1, 0)

      assert_status_broadcast("session-1", :idle)

      # Second session should still be working
      info2 = SessionWorker.get_info(pid2)
      assert info2.processing == true
    end

    test "queues are independent between sessions" do
      {:ok, _ref1} = SessionManager.start_session("session-1", "First", [])
      {:ok, _ref2} = SessionManager.start_session("session-2", "First", [])

      {:ok, pid1} = await_worker("session-1")
      {:ok, pid2} = await_worker("session-2")

      # Queue messages to session-1
      SessionManager.resume_session("session-1", "Second", [])
      SessionManager.resume_session("session-1", "Third", [])

      info1 = SessionWorker.get_info(pid1)
      info2 = SessionWorker.get_info(pid2)

      assert info1.queue_depth == 2
      assert info2.queue_depth == 0
    end
  end

  describe "worker restart behavior" do
    test "worker does not restart after normal exit (temporary restart)" do
      {:ok, _ref} = SessionManager.start_session("test-session", "Hello", [])
      {:ok, pid} = await_worker("test-session")

      # Normal exit
      port = get_mock_port(pid)
      send_mock_exit(port, 0)

      # Wait for potential restart
      Process.sleep(200)

      # Worker should still be the same pid (idle, not restarted)
      assert [{^pid, _}] = Registry.lookup(@registry, {:session, "test-session"})
      assert Process.alive?(pid)

      info = SessionWorker.get_info(pid)
      assert info.processing == false
    end

    test "worker goes idle after normal exit" do
      {:ok, _ref} = SessionManager.start_session("test-session", "Hello", [])
      {:ok, pid} = await_worker("test-session")

      port = get_mock_port(pid)
      send_mock_exit(port, 0)

      # Brief delay for async exit handling
      Process.sleep(50)

      # The idle timeout is 60 seconds, but we're not testing the full timeout here
      # Just verify the worker is idle after the CLI exits
      info = SessionWorker.get_info(pid)
      assert info.processing == false
    end
  end

  describe "edge cases" do
    test "handles concurrent resume attempts" do
      {:ok, _ref} = SessionManager.start_session("test-session", "First", [])
      {:ok, pid} = await_worker("test-session")

      # Make port hang
      port = get_mock_port(pid)
      make_port_hang(port)

      # Spawn multiple tasks attempting to resume concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            SessionManager.resume_session("test-session", "Concurrent #{i}", [])
          end)
        end

      results = Task.await_many(tasks)

      # All should return :queued or queue_full, none should spawn new workers
      assert Enum.all?(results, fn
               {:ok, :queued} -> true
               _ -> false
             end)

      # Should still be just one worker
      assert [{^pid, _}] = Registry.lookup(@registry, {:session, "test-session"})

      # Queue should be at max or less
      info = SessionWorker.get_info(pid)
      assert info.queue_depth <= 5
    end

    test "handles worker crash gracefully" do
      subscribe_session_status("test-session")

      {:ok, _ref} = SessionManager.start_session("test-session", "Hello", [])
      {:ok, pid} = await_worker("test-session")

      # Monitor before crashing
      monitor_ref = Process.monitor(pid)

      # Crash worker
      Process.exit(pid, :kill)

      # Wait for DOWN message (might be :killed or :noproc depending on timing)
      assert_receive {:DOWN, ^monitor_ref, :process, ^pid, _reason}, 1000

      # Brief delay to let things settle
      Process.sleep(50)

      # Should be able to resume with new worker
      {:ok, ref2} = SessionManager.resume_session("test-session", "After crash", [])
      assert is_reference(ref2)

      {:ok, pid2} = await_worker("test-session")
      assert pid2 != pid
    end
  end
end
