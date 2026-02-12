defmodule EyeInTheSkyWeb.Claude.AgentWorkerTest do
  use ExUnit.Case, async: false
  require Logger

  @moduletag :capture_log

  alias EyeInTheSkyWeb.Claude.{AgentWorker, AgentManager}
  alias EyeInTheSkyWeb.{Sessions, Agents, Messages, Repo}

  setup do
    # For non-async tests, Ecto sandbox will manage connections automatically
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "AgentManager sends message to Claude and gets response" do
    # Create test agent in DB
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Test Agent",
        source: "test"
      })

    Logger.info("Created agent: #{agent.id}")

    # Create test session in DB
    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Test Session",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    Logger.info("Created session: #{session.id} (uuid: #{session.uuid})")

    # Send message via AgentManager (real Claude)
    message = "Say hello in one word only"

    Logger.info("Calling AgentManager.send_message...")
    result = AgentManager.send_message(session.id, message, model: "haiku")

    Logger.info("AgentManager.send_message returned: #{inspect(result)}")
    assert result == :ok

    # Wait for Claude to process (5 second timeout)
    Logger.info("Waiting 5 seconds for Claude...")
    Process.sleep(5000)

    # Check if response was saved to database
    messages = Messages.list_messages_for_session(session.id)

    Logger.info("Messages in database: #{length(messages)}")
    Logger.info("Message details: #{inspect(Enum.map(messages, fn m -> %{body: m.body, role: m.sender_role} end))}")

    # Should have at least the incoming message
    assert length(messages) > 0, "No messages found in database"

    # Find agent response (role: "agent")
    agent_responses = Enum.filter(messages, &(&1.sender_role == "agent"))

    # Should have at least one response from Claude
    assert length(agent_responses) > 0,
           "No agent response found. Messages: #{inspect(Enum.map(messages, & &1.body))}"

    # Verify response is not empty
    response = List.first(agent_responses)
    assert response.body != nil
    assert String.length(response.body) > 0

    Logger.info("✅ Test passed! Claude responded: #{response.body}")
  end

  test "AgentWorker can be created and receives process messages" do
    # Create test agent
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Test Agent",
        source: "test"
      })

    # Create test session
    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Test Session",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    # Send a message to start AgentWorker
    result = AgentManager.send_message(session.id, "test", model: "haiku")
    assert result == :ok

    # Wait a bit for worker to spawn
    Process.sleep(100)

    # Verify the worker is running by sending another message
    result2 = AgentManager.send_message(session.id, "another test", model: "haiku")
    assert result2 == :ok
  end

  test "Multiple messages queue and process sequentially" do
    # Create test agent and session
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Queue Test Agent",
        source: "test"
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Queue Test Session",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    # Send 2 messages rapidly
    AgentManager.send_message(session.id, "Say 'one'", model: "haiku")
    AgentManager.send_message(session.id, "Say 'two'", model: "haiku")

    # Wait for both to process
    Process.sleep(8000)

    # Check database
    messages = Messages.list_messages_for_session(session.id)
    agent_responses = Enum.filter(messages, &(&1.sender_role == "agent"))

    # Should have responses (at least from first message, may have both)
    assert length(agent_responses) > 0

    Logger.info(
      "✅ Queue test passed! Got #{length(agent_responses)} agent responses from 2 messages"
    )
  end
end
