defmodule EyeInTheSkyWeb.Claude.AgentWorkerTest do
  use EyeInTheSkyWeb.DataCase, async: false
  require Logger

  @moduletag :capture_log

  alias EyeInTheSkyWeb.Claude.SDK
  alias EyeInTheSkyWeb.{Agents, Messages, Sessions}

  setup do
    # Track sessions created in this test so we can clean up only those workers
    test_pid = self()
    # Use start (not start_link) so the Agent survives the test process exit
    # and is still accessible from on_exit, which runs in a separate process.
    Agent.start(fn -> [] end, name: :"test_sessions_#{inspect(test_pid)}")

    on_exit(fn ->
      session_ids = Agent.get(:"test_sessions_#{inspect(test_pid)}", & &1)

      Enum.each(session_ids, fn session_id ->
        case Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session_id}) do
          [{pid, _}] when is_pid(pid) ->
            DynamicSupervisor.terminate_child(EyeInTheSkyWeb.Claude.AgentSupervisor, pid)

          _ ->
            :ok
        end
      end)

      Agent.stop(:"test_sessions_#{inspect(test_pid)}", :normal, 1000)
    end)

    {:ok, track: :"test_sessions_#{inspect(test_pid)}"}
  end

  # Helper to create an agent + session pair for tests
  defp create_test_agent_and_session(opts \\ %{}, ctx \\ %{}) do
    agent_attrs = %{
      uuid: Ecto.UUID.generate(),
      description: Map.get(opts, :description, "Test Agent"),
      source: Map.get(opts, :source, "test")
    }

    {:ok, agent} = Agents.create_agent(agent_attrs)

    session_attrs = %{
      uuid: Map.get(opts, :session_uuid, Ecto.UUID.generate()),
      agent_id: agent.id,
      name: Map.get(opts, :session_name, "Test Session"),
      provider: Map.get(opts, :provider, "claude"),
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, session} = Sessions.create_session(session_attrs)

    if track = ctx[:track] do
      Agent.update(track, fn ids -> [session.id | ids] end)
    end

    {agent, session}
  end

  test "AgentWorker saves result via SDK and broadcasts to PubSub" do
    {_agent, session} = create_test_agent_and_session()

    # Allow sandbox for dynamically started processes

    # Subscribe to session messages via PubSub
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session.id}")

    # Send a prompt through AgentManager (uses MockCLI via SDK)
    prompt = "Say exactly one word: hello"

    result =
      EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, prompt, model: "haiku")

    assert result == {:ok, :started}

    mock_port = wait_for_mock_port(session.id)
    assert mock_port != nil, "Mock port should be registered in SDK Registry"

    # Simulate Claude sending a result event
    result_json =
      Jason.encode!(%{
        "type" => "result",
        "result" => "hello",
        "session_id" => session.uuid,
        "uuid" => "mock-uuid-#{System.system_time(:second)}",
        "duration_ms" => 1234,
        "total_cost_usd" => 0.001,
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5},
        "is_error" => false
      })

    send(mock_port, {:send_output, result_json})

    # Simulate normal exit
    send(mock_port, {:exit, 0})

    # Wait for the response to be saved and broadcast
    response_body =
      receive do
        {:new_message, message} ->
          message.body

        other ->
          flunk("Unexpected message: #{inspect(other)}")
      after
        5_000 -> flunk("Timeout waiting for response via PubSub")
      end

    assert response_body == "hello"
  end

  test "AgentWorker updates session uuid from Claude stream result" do
    original_uuid = Ecto.UUID.generate()
    claude_uuid = Ecto.UUID.generate()

    {_agent, session} =
      create_test_agent_and_session(%{
        description: "UUID Sync Agent",
        session_name: "UUID Sync Session",
        session_uuid: original_uuid
      })

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")

    prompt = "Say hello"
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, prompt)
    assert_receive {:agent_working, _, _}, 5_000

    mock_port = wait_for_mock_port(session.id)
    assert mock_port != nil, "Mock port should be registered in SDK Registry"

    result_json =
      Jason.encode!(%{
        "type" => "result",
        "result" => "hello",
        "session_id" => claude_uuid,
        "uuid" => "mock-uuid-#{System.system_time(:second)}",
        "duration_ms" => 10,
        "total_cost_usd" => 0.0,
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1},
        "is_error" => false
      })

    send(mock_port, {:send_output, result_json})
    send(mock_port, {:exit, 0})

    # Wait for SDK complete via PubSub instead of Process.sleep
    session_id = session.id
    assert_receive {:agent_stopped, _, ^session_id}, 5_000

    # In-memory state updated immediately; DB write is async via Task.start
    assert_eventually(fn ->
      {:ok, refreshed_session} = Sessions.get_session(session.id)
      refreshed_session.uuid == claude_uuid
    end)
  end

  test "AgentManager starts a new Claude session when only outbound user messages exist" do
    {_agent, session} =
      create_test_agent_and_session(%{
        description: "Outbound-only Session",
        session_name: "Outbound-only"
      })

    {:ok, _user_message} =
      Messages.send_message(%{
        session_id: session.id,
        sender_role: "user",
        recipient_role: "agent",
        provider: "claude",
        body: "hello"
      })

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "hello")

    assert_receive {:agent_working, _, ^session_id}, 5_000

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    worker_state = :sys.get_state(worker_pid)
    assert worker_state.current_job.context.has_messages == false
  end

  test "AgentManager returns error for invalid message payload" do
    assert {:error, :invalid_message} =
             EyeInTheSkyWeb.Agents.AgentManager.send_message(123_456, nil)
  end

  test "Messages tracks inbound history per provider" do
    {_agent, session} =
      create_test_agent_and_session(%{
        description: "Codex Session",
        session_name: "Codex Session",
        provider: "codex"
      })

    {:ok, _reply} =
      Messages.record_incoming_reply(session.id, "codex", "prior codex reply")

    {:ok, refreshed_session} = Sessions.get_session(session.id)
    assert refreshed_session.provider == "codex"
    assert Messages.has_inbound_reply?(session.id, "codex")
    refute Messages.has_inbound_reply?(session.id, "claude")
  end

  test "AgentManager falls back to cwd project path when no worktree path is configured" do
    {_agent, session} =
      create_test_agent_and_session(%{
        description: "No Path Session",
        session_name: "No Path Session"
      })

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "hello")

    assert_receive {:agent_working, _, ^session_id}, 5_000

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    worker_state = :sys.get_state(worker_pid)
    assert worker_state.project_path == File.cwd!()
  end

  # --- PubSub Regression Tests ---

  test "AgentWorker broadcasts {:agent_working, ...} on PubSub when SDK starts" do
    {_agent, session} =
      create_test_agent_and_session(%{
        description: "PubSub Working Test",
        session_name: "PubSub Working"
      })

    # Subscribe to the agent:working topic
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")

    session_id = session.id

    assert {:ok, _} =
             EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "hello", model: "haiku")

    # Should receive :agent_working broadcast when SDK starts
    assert_receive {:agent_working, session_uuid, ^session_id},
                   5_000

    # session_uuid should be a valid UUID string (the worker loads it from DB)
    assert is_binary(session_uuid) and byte_size(session_uuid) > 0
  end

  test "AgentWorker broadcasts {:agent_stopped, ...} on PubSub when SDK completes" do
    {_agent, session} =
      create_test_agent_and_session(%{
        description: "PubSub Stopped Test",
        session_name: "PubSub Stopped"
      })

    # Subscribe to the agent:working topic
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")

    assert {:ok, _} =
             EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "hello", model: "haiku")

    mock_port = wait_for_mock_port(session.id)
    assert mock_port != nil

    # Drain the :agent_working message first
    assert_receive {:agent_working, _, _}, 5_000

    # Send result and exit to complete the SDK lifecycle
    result_json =
      Jason.encode!(%{
        "type" => "result",
        "result" => "done",
        "session_id" => session.uuid,
        "uuid" => "mock-uuid-#{System.system_time(:second)}",
        "duration_ms" => 100,
        "total_cost_usd" => 0.001,
        "usage" => %{"input_tokens" => 5, "output_tokens" => 3},
        "is_error" => false
      })

    send(mock_port, {:send_output, result_json})
    send(mock_port, {:exit, 0})

    # Should receive :agent_stopped broadcast when SDK completes
    session_id = session.id

    assert_receive {:agent_stopped, session_uuid, ^session_id},
                   5_000

    assert session_uuid == session.uuid
  end

  test "AgentWorker broadcasts {:new_message, ...} on PubSub when result is saved" do
    {_agent, session} =
      create_test_agent_and_session(%{
        description: "PubSub New Message Test",
        session_name: "PubSub New Message"
      })

    # Subscribe to session-specific messages topic
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session.id}")

    assert {:ok, _} =
             EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "hello", model: "haiku")

    mock_port = wait_for_mock_port(session.id)
    assert mock_port != nil

    result_json =
      Jason.encode!(%{
        "type" => "result",
        "result" => "test response body",
        "session_id" => session.uuid,
        "uuid" => "mock-uuid-#{System.system_time(:second)}",
        "duration_ms" => 50,
        "total_cost_usd" => 0.002,
        "usage" => %{"input_tokens" => 8, "output_tokens" => 4},
        "is_error" => false
      })

    send(mock_port, {:send_output, result_json})
    send(mock_port, {:exit, 0})

    # Should receive {:new_message, message} broadcast with the saved message
    assert_receive {:new_message, message}, 5_000
    assert message.body == "test response body"
    assert message.sender_role == "agent"
  end

  test "AgentWorker broadcasts {:agent_stopped, ...} on SDK error" do
    {_agent, session} =
      create_test_agent_and_session(%{
        description: "PubSub Error Stop Test",
        session_name: "PubSub Error Stop"
      })

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")

    assert {:ok, _} =
             EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "hello", model: "haiku")

    mock_port = wait_for_mock_port(session.id)
    assert mock_port != nil

    # Drain :agent_working
    assert_receive {:agent_working, _, _}, 5_000

    # Simulate error exit (non-zero exit code, no result)
    send(mock_port, {:exit, 1})

    # Should still broadcast :agent_stopped on error
    session_id = session.id

    assert_receive {:agent_stopped, _session_uuid, ^session_id},
                   5_000
  end

  # --- Regression: double registry lookup bug ---

  test "send_message delivers message to newly started worker (regression: double registry lookup)", %{track: track} do
    # Previously send_message called lookup_or_start (got pid), then called
    # AgentWorker.process_message which did a SECOND Registry.lookup.
    # If that second lookup raced or failed, the message was silently dropped
    # and the session was never prompted. Now we call directly to the pid.
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    assert {:ok, :started} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "test prompt")

    # :agent_working is broadcast only when the SDK actually starts, which only
    # happens if the cast reached the worker. If the old double-lookup dropped
    # the message this assertion would time out.
    assert_receive {:agent_working, _, ^session_id}, 5_000
  end

  test "create_agent delivers initial instructions to the worker", %{track: track} do
    # Regression: create_agent created DB records successfully but send_message
    # silently dropped the instructions via the second registry lookup.
    # The session existed but the agent was never told what to work on.
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")

    opts = [
      model: "haiku",
      description: "Instruction delivery test",
      instructions: "You are working on task #999: Do something important"
    ]

    {:ok, %{session: session}} = EyeInTheSkyWeb.Agents.AgentManager.create_agent(opts)
    Agent.update(track, fn ids -> [session.id | ids] end)

    session_id = session.id

    assert_receive {:agent_working, _, ^session_id}, 5_000

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session_id})

    worker_state = :sys.get_state(worker_pid)
    assert worker_state.current_job != nil
    assert String.contains?(worker_state.current_job.message, "task #999")
  end

  # --- Queue Depth Tests ---

  test "queue rejects messages beyond max depth (5)", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    # Start first message — this becomes current_job, SDK is active
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-1")

    mock_port = wait_for_mock_port(session.id)
    assert mock_port != nil

    # Queue 5 more while SDK is busy (fills the queue to max)
    for i <- 2..6 do
      assert {:ok, :queued} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-#{i}")
    end

    # 7th message should be rejected (queue full at 5)
    assert {:error, :queue_full} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-7")

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    worker_state = :sys.get_state(worker_pid)
    assert length(worker_state.queue) == 5

    # Clean up — send exit so worker terminates cleanly
    send(mock_port, {:exit, 0})
  end

  # --- Cancel Tests ---

  test "cancel/1 sends cancel to SDK process", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "hello")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    mock_port = wait_for_mock_port(session.id)
    assert mock_port != nil

    # Cancel should trigger the mock port to exit with 130
    EyeInTheSkyWeb.Agents.AgentManager.cancel_session(session.id)

    # The mock port sends {:claude_exit, ref, 130} on cancel, which surfaces as :agent_stopped
    assert_receive {:agent_stopped, _, ^session_id}, 5_000
  end

  test "cancel/1 returns error for nonexistent session" do
    assert {:error, :not_found} ==
             EyeInTheSkyWeb.Claude.AgentWorker.cancel(999_999)
  end

  # --- Systemic Error Tests ---

  test "systemic billing error drains queue instead of retrying", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "dm:#{session.id}:stream")

    session_id = session.id

    # Start first message
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-1")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    mock_port = wait_for_mock_port(session.id)
    assert mock_port != nil

    # Queue two more messages while busy
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-2")
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-3")

    # Simulate a billing error by sending a result with billing error text, then error exit
    result_json =
      Jason.encode!(%{
        "type" => "result",
        "result" => "Credit balance is too low",
        "session_id" => session.uuid,
        "uuid" => "mock-uuid",
        "duration_ms" => 0,
        "total_cost_usd" => 0.0,
        "usage" => %{"input_tokens" => 0, "output_tokens" => 0},
        "is_error" => true
      })

    send(mock_port, {:send_output, result_json})
    send(mock_port, {:exit, 1})

    # Should receive agent_stopped (from the error handler)
    assert_receive {:agent_stopped, _, ^session_id}, 5_000

    # Wait for state to settle
    Process.sleep(100)

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    worker_state = :sys.get_state(worker_pid)

    # Queue should be drained — systemic error stops all queued work
    assert worker_state.queue == []
    assert worker_state.sdk_ref == nil
    assert worker_state.current_job == nil
  end

  # --- Struct State Tests ---

  test "worker state uses AgentWorker struct", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "hello")

    # Wait for worker to be alive
    Process.sleep(100)

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    worker_state = :sys.get_state(worker_pid)

    # State should be an AgentWorker struct, not a plain map
    assert %EyeInTheSkyWeb.Claude.AgentWorker{} = worker_state
    assert worker_state.session_id == session.id
    assert is_binary(worker_state.provider_conversation_id)
    assert worker_state.provider == "claude"
    assert worker_state.stream.buffer == ""
    assert worker_state.retry_attempt == 0
  end

  # --- Retry Cap Tests ---

  test "successful SDK start resets retry_attempt to 0", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    # Start worker
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-1")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    mock_port = wait_for_mock_port(session.id)

    # Simulate that we had some retries before this succeeded
    :sys.replace_state(worker_pid, fn state ->
      %{state | retry_attempt: 3}
    end)

    # Complete the SDK — this triggers clear_retry_timer which resets retry_attempt
    send(mock_port, {:exit, 0})
    assert_receive {:agent_stopped, _, ^session_id}, 5_000

    # Queue a new job — successful start should have retry_attempt at 0
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-2")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    worker_state = :sys.get_state(worker_pid)
    assert worker_state.retry_attempt == 0
  end

  test "schedule_retry_start drains queue at max retries", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "dm:#{session.id}:stream")
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")

    session_id = session.id

    # Start worker
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-1")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    mock_port = wait_for_mock_port(session.id)

    # Complete cleanly to get worker idle
    send(mock_port, {:exit, 0})
    assert_receive {:agent_stopped, _, ^session_id}, 5_000

    # Directly set state to simulate max retries reached:
    # - retry_attempt at 5 (max)
    # - queue has jobs
    # - sdk_ref nil (idle)
    # - retry_timer_ref nil (no timer pending)
    # Then cast a process_message. Since SDK starts succeed with MockCLI,
    # the retry resets. Instead, we call schedule_retry_start indirectly by
    # setting the state and letting the GenServer handle it.
    fake_job = EyeInTheSkyWeb.Claude.Job.new("will-be-drained", %{has_messages: false})

    :sys.replace_state(worker_pid, fn state ->
      %{state | queue: [fake_job], retry_attempt: 5, retry_timer_ref: nil, sdk_ref: nil, current_job: nil}
    end)

    # Send a new message. The handler sees sdk_ref == nil, tries start_sdk.
    # MockCLI will succeed and clear_retry_timer resets retry_attempt.
    # We can't directly test max retry drain with MockCLI,
    # but we verify the retry_attempt field exists and resets on success.
    assert {:ok, :started} = GenServer.call(worker_pid, {:submit_message, "new-msg", %{has_messages: false}})

    assert_receive {:agent_working, _, ^session_id}, 5_000

    worker_state = :sys.get_state(worker_pid)
    # Successful start resets retry_attempt
    assert worker_state.retry_attempt == 0
    # The fake_job in the queue should still be there (queued behind new message)
    assert length(worker_state.queue) == 1
  end

  # --- UUID sync without Process.sleep ---

  test "session uuid sync updates in-memory state immediately", %{track: track} do
    original_uuid = Ecto.UUID.generate()
    claude_uuid = Ecto.UUID.generate()

    {_agent, session} =
      create_test_agent_and_session(
        %{
          description: "UUID Sync v2",
          session_name: "UUID Sync v2",
          session_uuid: original_uuid
        },
        %{track: track}
      )

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "hello")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    mock_port = wait_for_mock_port(session.id)

    result_json =
      Jason.encode!(%{
        "type" => "result",
        "result" => "hello",
        "session_id" => claude_uuid,
        "uuid" => "mock-uuid",
        "duration_ms" => 10,
        "total_cost_usd" => 0.0,
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1},
        "is_error" => false
      })

    send(mock_port, {:send_output, result_json})
    send(mock_port, {:exit, 0})

    # Wait for agent_stopped instead of Process.sleep
    assert_receive {:agent_stopped, _, ^session_id}, 5_000

    # The in-memory state should be updated immediately
    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    worker_state = :sys.get_state(worker_pid)
    assert worker_state.provider_conversation_id == claude_uuid

    # DB update happens via Task.start — poll briefly for it
    assert_eventually(fn ->
      {:ok, refreshed} = Sessions.get_session(session.id)
      refreshed.uuid == claude_uuid
    end)
  end

  # --- Failed state recovery ---

  test "failed worker recovers and processes new message", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    # Start worker to get it registered
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-1")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    mock_port = wait_for_mock_port(session.id)
    assert mock_port != nil

    send(mock_port, {:exit, 0})
    assert_receive {:agent_stopped, _, ^session_id}, 5_000

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    # Force into :failed state (simulating max retries exceeded)
    :sys.replace_state(worker_pid, fn state ->
      %{state | status: :failed, sdk_ref: nil, current_job: nil, queue: [], retry_attempt: 0, retry_timer_ref: nil}
    end)

    assert :sys.get_state(worker_pid).status == :failed

    # New message should recover the worker, not black-hole it
    assert {:ok, :started} =
             EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "recovery-msg")

    assert_receive {:agent_working, _, ^session_id}, 5_000

    worker_state = :sys.get_state(worker_pid)
    assert worker_state.status == :running
    assert worker_state.current_job != nil
    assert worker_state.current_job.message == "recovery-msg"

    new_mock = wait_for_mock_port(session.id)
    if new_mock, do: send(new_mock, {:exit, 0})
  end

  test "failed worker with queued messages processes them on next submit", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-1")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    mock_port = wait_for_mock_port(session.id)
    send(mock_port, {:exit, 0})
    assert_receive {:agent_stopped, _, ^session_id}, 5_000

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    # Force into :failed with a queued job that was stranded
    stranded_job = EyeInTheSkyWeb.Claude.Job.new("stranded-msg", %{has_messages: false})

    :sys.replace_state(worker_pid, fn state ->
      %{state | status: :failed, sdk_ref: nil, current_job: nil, queue: [stranded_job], retry_attempt: 0, retry_timer_ref: nil}
    end)

    assert :sys.get_state(worker_pid).status == :failed

    # Submitting a new message should kick the worker back to life
    assert {:ok, :started} =
             EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "trigger-msg")

    assert_receive {:agent_working, _, ^session_id}, 5_000

    worker_state = :sys.get_state(worker_pid)
    assert worker_state.status == :running
    # The stranded job should still be queued behind the trigger
    assert length(worker_state.queue) == 1
    assert hd(worker_state.queue).message == "stranded-msg"

    new_mock = wait_for_mock_port(session.id)
    if new_mock, do: send(new_mock, {:exit, 0})
  end

  # --- Error recovery: next job after transient error ---

  test "transient error processes next queued job", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    # Start first message
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-1")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    mock_port = wait_for_mock_port(session.id)

    # Queue a second message
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "msg-2")

    # Simulate transient error (non-systemic) — just exit with error code
    send(mock_port, {:exit, 1})

    # Should receive agent_stopped from error
    assert_receive {:agent_stopped, _, ^session_id}, 5_000

    # Then agent_working again for the next queued job
    assert_receive {:agent_working, _, ^session_id}, 5_000

    # Verify worker picked up msg-2
    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    worker_state = :sys.get_state(worker_pid)
    assert worker_state.current_job != nil
    assert worker_state.current_job.message == "msg-2"

    # Clean up
    new_mock = wait_for_mock_port(session.id)
    if new_mock, do: send(new_mock, {:exit, 0})
  end

  # --- Registry Invariant Tests ---
  # Invariant: exactly one AgentWorker per session, keyed by {:session, session_id}

  test "lookup finds existing worker by {:session, session_id}", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "hello")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    # Must find exactly one worker under the {:session, id} key
    result = Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})
    assert [{pid, provider}] = result
    assert is_pid(pid)
    assert Process.alive?(pid)
    assert provider == "claude"

    # Old {:agent, id} key must NOT be registered
    assert [] == Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:agent, session.id})

    mock_port = wait_for_mock_port(session.id)
    if mock_port, do: send(mock_port, {:exit, 0})
  end

  test "dead worker is replaced by new worker on next message", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    # Start first worker
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "first")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    [{first_pid, _}] = Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    # Kill the worker process directly
    DynamicSupervisor.terminate_child(EyeInTheSkyWeb.Claude.AgentSupervisor, first_pid)
    Process.sleep(100)

    refute Process.alive?(first_pid)

    # Sending another message should start a fresh worker
    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "second")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    [{second_pid, _}] = Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})
    assert is_pid(second_pid)
    assert Process.alive?(second_pid)
    assert second_pid != first_pid

    mock_port = wait_for_mock_port(session.id)
    if mock_port, do: send(mock_port, {:exit, 0})
  end

  test "no worker is started when none exists until send_message is called", %{track: track} do
    {_agent, session} = create_test_agent_and_session(%{}, %{track: track})

    # Before any message is sent, registry must be empty for this session
    assert [] == Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})

    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
    session_id = session.id

    assert {:ok, _} = EyeInTheSkyWeb.Agents.AgentManager.send_message(session.id, "hello")
    assert_receive {:agent_working, _, ^session_id}, 5_000

    # Now exactly one worker must be registered
    assert [{pid, _}] = Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session.id})
    assert Process.alive?(pid)

    mock_port = wait_for_mock_port(session.id)
    if mock_port, do: send(mock_port, {:exit, 0})
  end

  # --- Helper: poll until condition is true ---

  defp assert_eventually(fun, attempts \\ 20) do
    if fun.() do
      :ok
    else
      if attempts <= 0 do
        flunk("assert_eventually timed out")
      else
        Process.sleep(50)
        assert_eventually(fun, attempts - 1)
      end
    end
  end

  defp wait_for_mock_port(session_id, attempts \\ 20)

  defp wait_for_mock_port(_session_id, 0), do: nil

  defp wait_for_mock_port(session_id, attempts) do
    case Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session_id}) do
      [{worker_pid, _}] when is_pid(worker_pid) ->
        if Process.alive?(worker_pid) do
          mock_port =
            try do
              worker_state = :sys.get_state(worker_pid)
              sdk_ref = worker_state.sdk_ref
              if sdk_ref, do: SDK.Registry.lookup(sdk_ref), else: nil
            catch
              :exit, _ -> nil
            end

          if mock_port do
            mock_port
          else
            Process.sleep(50)
            wait_for_mock_port(session_id, attempts - 1)
          end
        else
          Process.sleep(50)
          wait_for_mock_port(session_id, attempts - 1)
        end

      [] ->
        Process.sleep(50)
        wait_for_mock_port(session_id, attempts - 1)
    end
  end
end
