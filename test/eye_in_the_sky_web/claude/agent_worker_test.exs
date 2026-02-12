defmodule EyeInTheSkyWeb.Claude.AgentWorkerTest do
  use ExUnit.Case, async: false
  require Logger

  alias EyeInTheSkyWeb.Claude.AgentWorker
  alias EyeInTheSkyWeb.{Repo}

  setup do
    # Allow database access in tests
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "AgentWorker initializes with correct state" do
    session_id = 123
    session_uuid = "test-uuid-#{:rand.uniform(999999)}"
    agent_id = "agent-id"
    project_path = File.cwd!()

    opts = [
      session_id: session_id,
      session_uuid: session_uuid,
      agent_id: agent_id,
      project_path: project_path
    ]

    # Start worker directly without Registry
    {:ok, pid} = GenServer.start_link(AgentWorker, opts)

    # Check initial state
    state = :sys.get_state(pid)

    assert state.session_id == session_id
    assert state.session_uuid == session_uuid
    assert state.agent_id == agent_id
    assert state.port == nil
    assert state.queue == []
    assert state.session_ref == nil
  end

  test "AgentWorker queues message when busy" do
    session_id = 123
    session_uuid = "test-uuid-#{:rand.uniform(999999)}"
    agent_id = "agent-id"

    opts = [
      session_id: session_id,
      session_uuid: session_uuid,
      agent_id: agent_id,
      project_path: File.cwd!()
    ]

    {:ok, pid} = GenServer.start_link(AgentWorker, opts)

    # Simulate agent being busy
    fake_port = Port.open({:spawn, "cat"}, [:binary])
    fake_ref = make_ref()

    :sys.replace_state(pid, fn state ->
      %{state | port: fake_port, session_ref: fake_ref}
    end)

    # Send message via cast
    GenServer.cast(pid, {:process_message, "test message", %{model: "sonnet", has_messages: false}})

    Process.sleep(100)

    state = :sys.get_state(pid)

    # Should be queued
    assert length(state.queue) == 1
    assert List.first(state.queue).message == "test message"

    Port.close(fake_port)
  end

  test "AgentWorker does not spawn Claude if already busy" do
    session_id = 123
    session_uuid = "test-uuid-#{:rand.uniform(999999)}"
    agent_id = "agent-id"

    opts = [
      session_id: session_id,
      session_uuid: session_uuid,
      agent_id: agent_id,
      project_path: File.cwd!()
    ]

    {:ok, pid} = GenServer.start_link(AgentWorker, opts)

    # Set busy
    fake_port = Port.open({:spawn, "cat"}, [:binary])
    fake_ref = make_ref()

    :sys.replace_state(pid, fn state ->
      %{state | port: fake_port, session_ref: fake_ref}
    end)

    state_before = :sys.get_state(pid)

    # Send message (should queue, not spawn)
    GenServer.cast(pid, {:process_message, "msg", %{model: "sonnet", has_messages: false}})

    Process.sleep(100)

    state_after = :sys.get_state(pid)

    # Port should be the same (not replaced)
    assert state_after.port == state_before.port
    assert length(state_after.queue) == 1

    Port.close(fake_port)
  end

  test "AgentWorker processes next queued message when current finishes" do
    session_id = 123
    session_uuid = "test-uuid-#{:rand.uniform(999999)}"
    agent_id = "agent-id"

    opts = [
      session_id: session_id,
      session_uuid: session_uuid,
      agent_id: agent_id,
      project_path: File.cwd!()
    ]

    {:ok, pid} = GenServer.start_link(AgentWorker, opts)

    # Simulate busy with queued messages
    fake_port = Port.open({:spawn, "cat"}, [:binary])
    fake_ref = make_ref()

    msg1 = %{message: "msg1", context: %{model: "sonnet", has_messages: false}, queued_at: DateTime.utc_now()}
    msg2 = %{message: "msg2", context: %{model: "sonnet", has_messages: true}, queued_at: DateTime.utc_now()}

    :sys.replace_state(pid, fn state ->
      %{state | port: fake_port, session_ref: fake_ref, queue: [msg1, msg2]}
    end)

    state_before = :sys.get_state(pid)
    assert length(state_before.queue) == 2

    # Send exit notification for current Claude
    send(pid, {:claude_exit, fake_ref, 0})

    Process.sleep(200)

    state_after = :sys.get_state(pid)

    # Queue should be processed (reduced by 1)
    # Note: Can't spawn real Claude so port will be nil
    assert length(state_after.queue) <= 1

    Port.close(fake_port)
  end

  test "AgentWorker goes idle when queue empties" do
    session_id = 123
    session_uuid = "test-uuid-#{:rand.uniform(999999)}"
    agent_id = "agent-id"

    opts = [
      session_id: session_id,
      session_uuid: session_uuid,
      agent_id: agent_id,
      project_path: File.cwd!()
    ]

    {:ok, pid} = GenServer.start_link(AgentWorker, opts)

    # Simulate busy with empty queue
    fake_port = Port.open({:spawn, "cat"}, [:binary])
    fake_ref = make_ref()

    :sys.replace_state(pid, fn state ->
      %{state | port: fake_port, session_ref: fake_ref, queue: []}
    end)

    # Send exit
    send(pid, {:claude_exit, fake_ref, 0})

    Process.sleep(100)

    state = :sys.get_state(pid)

    # Should be idle
    assert state.port == nil
    assert state.session_ref == nil
    assert state.queue == []

    Port.close(fake_port)
  end

  test "AgentWorker handles multiple queued messages in FIFO order" do
    session_id = 123
    session_uuid = "test-uuid-#{:rand.uniform(999999)}"
    agent_id = "agent-id"

    opts = [
      session_id: session_id,
      session_uuid: session_uuid,
      agent_id: agent_id,
      project_path: File.cwd!()
    ]

    {:ok, pid} = GenServer.start_link(AgentWorker, opts)

    # Simulate busy
    fake_port = Port.open({:spawn, "cat"}, [:binary])

    :sys.replace_state(pid, fn state ->
      %{state | port: fake_port, session_ref: make_ref()}
    end)

    # Send 5 messages
    for i <- 1..5 do
      GenServer.cast(
        pid,
        {:process_message,
         "message #{i}",
         %{model: "sonnet", has_messages: false}}
      )
    end

    Process.sleep(200)

    state = :sys.get_state(pid)

    # All 5 should be queued
    assert length(state.queue) == 5

    # Verify FIFO order
    messages = Enum.map(state.queue, & &1.message)
    expected = ["message 1", "message 2", "message 3", "message 4", "message 5"]
    assert messages == expected

    Port.close(fake_port)
  end

  test "AgentWorker ignores mismatched session_ref on exit" do
    session_id = 123
    session_uuid = "test-uuid-#{:rand.uniform(999999)}"
    agent_id = "agent-id"

    opts = [
      session_id: session_id,
      session_uuid: session_uuid,
      agent_id: agent_id,
      project_path: File.cwd!()
    ]

    {:ok, pid} = GenServer.start_link(AgentWorker, opts)

    fake_port = Port.open({:spawn, "cat"}, [:binary])
    correct_ref = make_ref()
    wrong_ref = make_ref()

    :sys.replace_state(pid, fn state ->
      %{state | port: fake_port, session_ref: correct_ref}
    end)

    # Send exit with wrong ref
    send(pid, {:claude_exit, wrong_ref, 0})

    Process.sleep(100)

    state = :sys.get_state(pid)

    # Should still be busy
    assert state.port == fake_port
    assert state.session_ref == correct_ref

    Port.close(fake_port)
  end

  test "AgentWorker handles claude_output messages" do
    session_id = 123
    session_uuid = "test-uuid-#{:rand.uniform(999999)}"
    agent_id = "agent-id"

    opts = [
      session_id: session_id,
      session_uuid: session_uuid,
      agent_id: agent_id,
      project_path: File.cwd!()
    ]

    {:ok, pid} = GenServer.start_link(AgentWorker, opts)

    state_before = :sys.get_state(pid)

    # Send output message (should be ignored)
    send(pid, {:claude_output, make_ref(), "test output"})

    Process.sleep(100)

    state_after = :sys.get_state(pid)

    # State should be unchanged
    assert state_before == state_after
  end
end
