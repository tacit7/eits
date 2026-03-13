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
        case Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:agent, session_id}) do
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
      EyeInTheSkyWeb.Claude.AgentManager.send_message(session.id, prompt, model: "haiku")

    assert result == :ok

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

    prompt = "Say hello"
    assert :ok == EyeInTheSkyWeb.Claude.AgentManager.send_message(session.id, prompt)

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

    Process.sleep(200)

    {:ok, refreshed_session} = Sessions.get_session(session.id)
    assert refreshed_session.uuid == claude_uuid
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

    assert :ok == EyeInTheSkyWeb.Claude.AgentManager.send_message(session.id, "hello")

    Process.sleep(200)

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:agent, session.id})

    worker_state = :sys.get_state(worker_pid)
    assert worker_state.current_job.context.has_messages == false
  end

  test "AgentManager returns error for invalid message payload" do
    assert {:error, :invalid_message} =
             EyeInTheSkyWeb.Claude.AgentManager.send_message(123_456, nil)
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

    assert :ok == EyeInTheSkyWeb.Claude.AgentManager.send_message(session.id, "hello")

    Process.sleep(200)

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:agent, session.id})

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

    assert :ok ==
             EyeInTheSkyWeb.Claude.AgentManager.send_message(session.id, "hello", model: "haiku")

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

    assert :ok ==
             EyeInTheSkyWeb.Claude.AgentManager.send_message(session.id, "hello", model: "haiku")

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

    assert :ok ==
             EyeInTheSkyWeb.Claude.AgentManager.send_message(session.id, "hello", model: "haiku")

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

    assert :ok ==
             EyeInTheSkyWeb.Claude.AgentManager.send_message(session.id, "hello", model: "haiku")

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

  defp wait_for_mock_port(session_id, attempts \\ 20)

  defp wait_for_mock_port(_session_id, 0), do: nil

  defp wait_for_mock_port(session_id, attempts) do
    case Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:agent, session_id}) do
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
