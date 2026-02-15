defmodule EyeInTheSkyWeb.Claude.AgentWorkerTest do
  use ExUnit.Case, async: false
  require Logger

  @moduletag :capture_log

  alias EyeInTheSkyWeb.Claude.SDK
  alias EyeInTheSkyWeb.{Agents, ChatAgents, Messages, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "AgentWorker saves result via SDK and broadcasts to PubSub" do
    # Create test chat agent
    {:ok, chat_agent} =
      ChatAgents.create_chat_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Test Agent",
        source: "test"
      })

    # Create test execution agent
    {:ok, execution_agent} =
      Agents.create_execution_agent(%{
        uuid: Ecto.UUID.generate(),
        agent_id: chat_agent.id,
        name: "Test Session",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    # Allow sandbox for dynamically started processes
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Subscribe to session messages via PubSub
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{execution_agent.id}")

    # Send a prompt through AgentManager (uses MockCLI via SDK)
    prompt = "Say exactly one word: hello"

    result =
      EyeInTheSkyWeb.Claude.AgentManager.send_message(execution_agent.id, prompt, model: "haiku")

    assert result == :ok

    # Give AgentWorker time to start SDK and spawn mock port
    Process.sleep(200)

    # Get the mock port from SDK Registry via AgentWorker state
    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:agent, execution_agent.id})

    worker_state = :sys.get_state(worker_pid)
    sdk_ref = worker_state.sdk_ref
    assert sdk_ref != nil, "SDK ref should be set after starting"

    mock_port = SDK.Registry.lookup(sdk_ref)
    assert mock_port != nil, "Mock port should be registered in SDK Registry"

    # Simulate Claude sending a result event
    result_json =
      Jason.encode!(%{
        "type" => "result",
        "result" => "hello",
        "session_id" => execution_agent.uuid,
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

  test "AgentWorker updates execution session uuid from Claude stream result" do
    {:ok, chat_agent} =
      ChatAgents.create_chat_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "UUID Sync Agent",
        source: "test"
      })

    original_uuid = Ecto.UUID.generate()
    claude_uuid = Ecto.UUID.generate()

    {:ok, execution_agent} =
      Agents.create_execution_agent(%{
        uuid: original_uuid,
        agent_id: chat_agent.id,
        name: "UUID Sync Session",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    prompt = "Say hello"
    assert :ok == EyeInTheSkyWeb.Claude.AgentManager.send_message(execution_agent.id, prompt)

    Process.sleep(200)

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:agent, execution_agent.id})

    sdk_ref = :sys.get_state(worker_pid).sdk_ref
    mock_port = SDK.Registry.lookup(sdk_ref)

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

    {:ok, refreshed_agent} = Agents.get_execution_agent(execution_agent.id)
    assert refreshed_agent.uuid == claude_uuid
  end

  test "AgentManager starts a new Claude session when only outbound user messages exist" do
    {:ok, chat_agent} =
      ChatAgents.create_chat_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Outbound-only Session",
        source: "test"
      })

    {:ok, execution_agent} =
      Agents.create_execution_agent(%{
        uuid: Ecto.UUID.generate(),
        agent_id: chat_agent.id,
        name: "Outbound-only",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    {:ok, _user_message} =
      Messages.send_message(%{
        session_id: execution_agent.id,
        sender_role: "user",
        recipient_role: "agent",
        provider: "claude",
        body: "hello"
      })

    assert :ok == EyeInTheSkyWeb.Claude.AgentManager.send_message(execution_agent.id, "hello")

    Process.sleep(200)

    [{worker_pid, _}] =
      Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:agent, execution_agent.id})

    worker_state = :sys.get_state(worker_pid)
    assert worker_state.current_job.context.has_messages == false
  end
end
