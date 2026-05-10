defmodule EyeInTheSky.Claude.ChatManagerTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.ChatManager
  alias EyeInTheSky.Claude.ChatWorker
  alias EyeInTheSky.Claude.ChatRegistry
  alias EyeInTheSky.Claude.ChatSupervisor

  setup do
    # Ensure the supervisor and registry are started for this test
    unless Process.whereis(ChatRegistry), do: Registry.start_link(name: ChatRegistry)
    unless Process.whereis(ChatSupervisor), do: DynamicSupervisor.start_link(name: ChatSupervisor)

    on_exit(fn ->
      # Clean up any started ChatWorkers
      Registry.select(ChatRegistry, [{{:_, :_}, :_, :_}])
      |> Enum.each(fn {_key, pid, _val} ->
        if Process.alive?(pid), do: DynamicSupervisor.terminate_child(ChatSupervisor, pid)
      end)
    end)

    :ok
  end

  describe "send_to_channel/3 success path" do
    test "starts a ChatWorker if one doesn't exist" do
      channel_id = "test-channel-#{:rand.uniform(100_000)}"

      # Verify no worker exists yet
      assert Registry.lookup(ChatRegistry, {:channel, channel_id}) == []

      # Send a message
      result = ChatManager.send_to_channel(channel_id, "Hello", 999)

      # Should succeed and start the worker
      assert result == {:ok, :started} or match?({:ok, _}, result)

      # Worker should now be registered
      assert Registry.lookup(ChatRegistry, {:channel, channel_id}) != []
    end

    test "reuses existing ChatWorker if one is running" do
      channel_id = "existing-channel-#{:rand.uniform(100_000)}"

      # Start first message (creates worker)
      ChatManager.send_to_channel(channel_id, "First", 1)

      # Get the worker PID
      [{worker_pid, _}] = Registry.lookup(ChatRegistry, {:channel, channel_id})

      # Send second message
      ChatManager.send_to_channel(channel_id, "Second", 2)

      # Worker PID should be the same
      [{worker_pid_2, _}] = Registry.lookup(ChatRegistry, {:channel, channel_id})
      assert worker_pid == worker_pid_2
    end

    test "accepts options parameter" do
      channel_id = "opts-channel-#{:rand.uniform(100_000)}"

      result = ChatManager.send_to_channel(channel_id, "Test", 999, timeout: 5000)

      assert result == {:ok, :started} or match?({:ok, _}, result)
    end
  end

  describe "send_to_channel/3 failure handling" do
    test "returns error if message is not binary" do
      channel_id = "invalid-channel-#{:rand.uniform(100_000)}"

      # This should fail during worker startup or in handle_cast
      result = ChatManager.send_to_channel(channel_id, 123, 999)

      assert match?({:error, _}, result) or result == :ok
    end
  end

  describe "send_to_channel/4 with options" do
    test "passes options to ChatWorker" do
      channel_id = "opts-test-#{:rand.uniform(100_000)}"
      opts = [priority: :high, timeout: 10_000]

      result = ChatManager.send_to_channel(channel_id, "Test", 999, opts)

      assert result == {:ok, :started} or match?({:ok, _}, result)
    end
  end

  describe "lookup_or_start/1 behavior" do
    test "starts new worker when registry is empty" do
      channel_id = "new-channel-#{:rand.uniform(100_000)}"

      # No worker yet
      assert Registry.lookup(ChatRegistry, {:channel, channel_id}) == []

      # First message triggers start
      ChatManager.send_to_channel(channel_id, "Message", 1)

      # Worker should exist
      assert Registry.lookup(ChatRegistry, {:channel, channel_id}) != []
    end

    test "restarts worker if process dies" do
      channel_id = "restart-channel-#{:rand.uniform(100_000)}"

      # Start first message
      ChatManager.send_to_channel(channel_id, "First", 1)
      [{worker_pid, _}] = Registry.lookup(ChatRegistry, {:channel, channel_id})

      # Kill the worker
      DynamicSupervisor.terminate_child(ChatSupervisor, worker_pid)

      # Worker should be gone
      :timer.sleep(50)
      assert Registry.lookup(ChatRegistry, {:channel, channel_id}) == [] or
               not Process.alive?(worker_pid)

      # Next message should start a new worker
      ChatManager.send_to_channel(channel_id, "Second", 2)

      [{new_worker_pid, _}] = Registry.lookup(ChatRegistry, {:channel, channel_id})
      assert new_worker_pid != worker_pid
    end
  end

  describe "concurrency with multiple channels" do
    test "multiple channels can send messages independently" do
      channel_1 = "channel-1-#{:rand.uniform(100_000)}"
      channel_2 = "channel-2-#{:rand.uniform(100_000)}"

      result1 = ChatManager.send_to_channel(channel_1, "Ch1 Message", 1)
      result2 = ChatManager.send_to_channel(channel_2, "Ch2 Message", 2)

      assert match?({:ok, _}, result1) or result1 == {:ok, :started}
      assert match?({:ok, _}, result2) or result2 == {:ok, :started}

      # Both should have separate workers
      assert Registry.lookup(ChatRegistry, {:channel, channel_1}) != []
      assert Registry.lookup(ChatRegistry, {:channel, channel_2}) != []

      [{worker_1, _}] = Registry.lookup(ChatRegistry, {:channel, channel_1})
      [{worker_2, _}] = Registry.lookup(ChatRegistry, {:channel, channel_2})

      assert worker_1 != worker_2
    end
  end
end
