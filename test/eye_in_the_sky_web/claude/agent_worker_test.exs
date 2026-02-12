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

  test "AgentWorker prompts Claude and gets a response" do
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

    # Subscribe to session messages via PubSub
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session.id}")

    # Send a simple prompt to Claude
    prompt = "Say exactly one word: hello"
    result = AgentManager.send_message(session.id, prompt, model: "haiku")
    assert result == :ok

    # Wait for Claude response (up to 10 seconds)
    response_body =
      receive do
        {:new_message, message} ->
          message.body

        other ->
          flunk("Unexpected message: #{inspect(other)}")
      after
        10000 -> flunk("Timeout waiting for Claude response")
      end

    # Verify we got a response
    assert response_body != nil
    assert String.length(response_body) > 0

    IO.puts("✅ Claude responded: #{response_body}")
  end

end
