defmodule EyeInTheSky.AgentWorkerEventsErrorMessageTest do
  use EyeInTheSky.DataCase, async: false

  @moduletag :capture_log

  alias EyeInTheSky.{AgentWorkerEvents, Agents, Messages, Sessions}

  defp insert_session_fixture do
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Error Message Test Agent",
        source: "test"
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Error Message Test Session",
        provider: "pi",
        status: "working",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    session
  end

  test "on_session_failed persists a system message with the sanitized error" do
    session = insert_session_fixture()

    AgentWorkerEvents.on_session_failed(
      session.id,
      "pcid-123",
      {:pi_turn_error,
       "**Error · HTTP 400**\n\nYou're out of extra usage.\n\n_invalid_request_error_"}
    )

    messages = Messages.list_messages_for_session(session.id)

    assert Enum.any?(messages, fn m ->
             m.provider == "system" and m.body =~ "provider error" and
               m.body =~ "out of extra usage"
           end)
  end

  test "the system error message never contains key-like material" do
    session = insert_session_fixture()

    AgentWorkerEvents.on_session_failed(
      session.id,
      "pcid-456",
      {:pi_turn_error, "bad key sk-or-abcdef1234567890"}
    )

    messages = Messages.list_messages_for_session(session.id)
    system_msgs = Enum.filter(messages, &(&1.provider == "system"))
    assert length(system_msgs) >= 1

    for msg <- system_msgs do
      refute msg.body =~ "sk-or-abcdef1234567890"
    end
  end

  test "on_session_failed works for non-pi reasons (fallback inspect path)" do
    session = insert_session_fixture()

    AgentWorkerEvents.on_session_failed(
      session.id,
      "pcid-789",
      {:billing_error, "credit balance is too low"}
    )

    messages = Messages.list_messages_for_session(session.id)

    assert Enum.any?(messages, fn m ->
             m.provider == "system" and m.body =~ "provider error"
           end)
  end

  test "on_session_failed persists Codex errors as structured Codex messages" do
    session = insert_session_fixture()

    payload =
      Jason.encode!(%{
        "type" => "error",
        "status" => 400,
        "error" => %{
          "type" => "invalid_request_error",
          "message" =>
            "The 'gpt-5.2' model is not supported when using Codex with a ChatGPT account."
        }
      })

    AgentWorkerEvents.on_session_failed(session.id, "pcid-codex", {:codex_error, payload})

    message =
      session.id
      |> Messages.list_messages_for_session()
      |> Enum.find(&(&1.provider == "codex"))

    assert message
    assert message.body =~ "not supported"
    assert message.metadata["stream_type"] == "codex_error"
    assert message.metadata["status"] == 400
    assert message.metadata["error_type"] == "invalid_request_error"
    assert message.metadata["model"] == "gpt-5.2"
  end
end
