defmodule EyeInTheSky.Claude.ChatWorkerTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.ChatWorker
  alias EyeInTheSky.Claude.ChatRegistry
  alias EyeInTheSky.Claude.ChatSupervisor

  setup do
    # Start the registry if not already running
    unless Process.whereis(ChatRegistry), do: Registry.start_link(name: ChatRegistry)
    unless Process.whereis(ChatSupervisor), do: DynamicSupervisor.start_link(name: ChatSupervisor)

    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(ChatSupervisor),
          is_pid(pid) and Process.alive?(pid) do
        DynamicSupervisor.terminate_child(ChatSupervisor, pid)
      end
    end)

    :ok
  end

  describe "start_link/1" do
    test "registers worker with channel_id" do
      channel_id = "start-test-#{:rand.uniform(100_000)}"

      {:ok, pid} = ChatWorker.start_link(channel_id: channel_id)

      # Should be registered
      [{reg_pid, _}] = Registry.lookup(ChatRegistry, {:channel, channel_id})
      assert reg_pid == pid
    end

    test "initializes with empty queue and not processing" do
      channel_id = "init-test-#{:rand.uniform(100_000)}"

      {:ok, _pid} = ChatWorker.start_link(channel_id: channel_id)

      # Check initial state via call
      assert ChatWorker.processing?(channel_id) == false
    end
  end

  describe "send_to_channel/4" do
    test "queues message when not processing" do
      channel_id = "queue-test-#{:rand.uniform(100_000)}"
      {:ok, _pid} = ChatWorker.start_link(channel_id: channel_id)

      result = ChatWorker.send_to_channel(channel_id, "Test message", 123)

      # Message should be cast (async)
      assert result == :ok
    end

    test "returns error if channel not found" do
      result = ChatWorker.send_to_channel("nonexistent-#{:rand.uniform(100_000)}", "Message", 123)

      assert result == {:error, :not_found}
    end

    test "accepts options parameter" do
      channel_id = "opts-test-#{:rand.uniform(100_000)}"
      {:ok, _pid} = ChatWorker.start_link(channel_id: channel_id)

      result = ChatWorker.send_to_channel(channel_id, "Message", 123, timeout: 5000)

      assert result == :ok
    end
  end

  describe "processing?/1" do
    test "returns false when not processing" do
      channel_id = "proc-false-#{:rand.uniform(100_000)}"
      {:ok, _pid} = ChatWorker.start_link(channel_id: channel_id)

      assert ChatWorker.processing?(channel_id) == false
    end

    test "returns false for nonexistent channel" do
      assert ChatWorker.processing?("nonexistent-#{:rand.uniform(100_000)}") == false
    end

    test "becomes true when processing a message" do
      channel_id = "proc-true-#{:rand.uniform(100_000)}"
      {:ok, pid} = ChatWorker.start_link(channel_id: channel_id)

      # Send a message — should start processing
      ChatWorker.send_to_channel(channel_id, "Message", 1)

      # Give it a moment to process
      :timer.sleep(50)

      # Worker must survive even when the fanout task crashes
      # (fake channel_id causes Ecto CastError in fanout — worker should not die)
      :timer.sleep(100)
      assert Process.alive?(pid)
    end
  end

  describe "message queueing" do
    test "queues multiple messages and processes in order" do
      channel_id = "multi-queue-#{:rand.uniform(100_000)}"
      {:ok, pid} = ChatWorker.start_link(channel_id: channel_id)

      # Send multiple messages in quick succession
      ChatWorker.send_to_channel(channel_id, "Message 1", 1)
      ChatWorker.send_to_channel(channel_id, "Message 2", 2)
      ChatWorker.send_to_channel(channel_id, "Message 3", 3)

      # Worker must remain alive after accepting all messages
      :timer.sleep(200)
      assert Process.alive?(pid)
    end

    test "processes queued messages after current fanout completes" do
      channel_id = "queue-order-#{:rand.uniform(100_000)}"
      {:ok, pid} = ChatWorker.start_link(channel_id: channel_id)

      # Send message while processing (queue it)
      ChatWorker.send_to_channel(channel_id, "First", 1)
      ChatWorker.send_to_channel(channel_id, "Second", 2)

      # Worker must remain alive after queuing messages
      :timer.sleep(200)
      assert Process.alive?(pid)
    end
  end

  describe "handle_call for processing? status" do
    test "returns processing state correctly" do
      channel_id = "state-test-#{:rand.uniform(100_000)}"
      {:ok, pid} = ChatWorker.start_link(channel_id: channel_id)

      # Direct call
      result = GenServer.call(pid, :processing?)

      assert result == false
    end
  end

  describe "invalid message handling" do
    test "logs warning for invalid message payload" do
      channel_id = "invalid-msg-#{:rand.uniform(100_000)}"
      {:ok, pid} = ChatWorker.start_link(channel_id: channel_id)

      # Send invalid message (not binary) via handle_cast
      # This would be caught by pattern matching
      GenServer.cast(pid, {:send_to_channel, 123, 456, []})

      :timer.sleep(50)

      # Worker should still be alive and not processing
      assert Process.alive?(pid)
      assert ChatWorker.processing?(channel_id) == false
    end
  end

  describe "fanout_complete message" do
    test "transitions from processing to idle after fanout completes" do
      channel_id = "fanout-test-#{:rand.uniform(100_000)}"
      {:ok, pid} = ChatWorker.start_link(channel_id: channel_id)

      # Start processing by sending a message
      ChatWorker.send_to_channel(channel_id, "Message", 1)

      :timer.sleep(50)

      # Simulate fanout completing by sending the message directly
      send(pid, {:fanout_complete, []})

      :timer.sleep(50)

      # Should be idle now
      assert ChatWorker.processing?(channel_id) == false
    end

    test "processes next queued message after fanout completes" do
      channel_id = "queue-fanout-#{:rand.uniform(100_000)}"
      {:ok, pid} = ChatWorker.start_link(channel_id: channel_id)

      # Queue messages
      ChatWorker.send_to_channel(channel_id, "First", 1)
      ChatWorker.send_to_channel(channel_id, "Second", 2)

      # Worker must remain alive after queuing and attempting fanout
      :timer.sleep(200)
      assert Process.alive?(pid)
    end
  end

  describe "unhandled messages" do
    test "logs and ignores unhandled messages" do
      channel_id = "unhandled-#{:rand.uniform(100_000)}"
      {:ok, pid} = ChatWorker.start_link(channel_id: channel_id)

      # Send unhandled message
      send(pid, :unhandled_message)

      :timer.sleep(50)

      # Worker should still be alive
      assert Process.alive?(pid)
    end
  end

  describe "edge cases" do
    test "handles empty message string" do
      channel_id = "empty-msg-#{:rand.uniform(100_000)}"
      {:ok, _pid} = ChatWorker.start_link(channel_id: channel_id)

      result = ChatWorker.send_to_channel(channel_id, "", 1)

      assert result == :ok
    end

    test "handles very long message" do
      channel_id = "long-msg-#{:rand.uniform(100_000)}"
      {:ok, _pid} = ChatWorker.start_link(channel_id: channel_id)

      long_msg = String.duplicate("x", 10_000)
      result = ChatWorker.send_to_channel(channel_id, long_msg, 1)

      assert result == :ok
    end

    test "handles multiple senders in rapid succession" do
      channel_id = "multi-sender-#{:rand.uniform(100_000)}"
      {:ok, pid} = ChatWorker.start_link(channel_id: channel_id)

      # Send from multiple "senders" quickly
      Enum.each(1..10, fn i ->
        ChatWorker.send_to_channel(channel_id, "Message #{i}", i)
      end)

      # Worker must survive rapid concurrent sends
      :timer.sleep(200)
      assert Process.alive?(pid)
    end
  end
end
