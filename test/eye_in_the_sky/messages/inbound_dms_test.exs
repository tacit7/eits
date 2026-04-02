defmodule EyeInTheSky.Messages.InboundDmsTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.{Agents, Messages, Sessions}

  defp uniq, do: System.unique_integer([:positive])

  defp create_session do
    {:ok, agent} = Agents.create_agent(%{name: "dm-test-agent-#{uniq()}", status: "active"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "idle"
      })

    session
  end

  defp insert_dm(to_session_id, from_session_id, body) do
    {:ok, msg} =
      Messages.create_message(%{
        uuid: Ecto.UUID.generate(),
        session_id: to_session_id,
        to_session_id: to_session_id,
        from_session_id: from_session_id,
        sender_role: "agent",
        recipient_role: "agent",
        direction: "inbound",
        body: body,
        status: "delivered",
        provider: "claude"
      })

    msg
  end

  describe "list_inbound_dms/2" do
    test "returns empty list when session has no DMs" do
      session = create_session()
      assert Messages.list_inbound_dms(session.id) == []
    end

    test "returns DMs addressed to the given session" do
      receiver = create_session()
      sender = create_session()

      insert_dm(receiver.id, sender.id, "hello")
      insert_dm(receiver.id, sender.id, "world")

      dms = Messages.list_inbound_dms(receiver.id)
      assert length(dms) == 2
      assert Enum.all?(dms, &(&1.to_session_id == receiver.id))
    end

    test "does not return DMs addressed to a different session" do
      receiver = create_session()
      other = create_session()
      sender = create_session()

      insert_dm(other.id, sender.id, "not for you")

      assert Messages.list_inbound_dms(receiver.id) == []
    end

    test "does not return messages without from_session_id" do
      session = create_session()

      {:ok, _} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          session_id: session.id,
          to_session_id: session.id,
          from_session_id: nil,
          sender_role: "user",
          recipient_role: "agent",
          direction: "inbound",
          body: "system message",
          status: "delivered",
          provider: "claude"
        })

      assert Messages.list_inbound_dms(session.id) == []
    end

    test "respects limit parameter" do
      receiver = create_session()
      sender = create_session()

      for i <- 1..10, do: insert_dm(receiver.id, sender.id, "msg #{i}")

      dms = Messages.list_inbound_dms(receiver.id, 3)
      assert length(dms) == 3
    end

    test "returns messages in ascending order (oldest first)" do
      receiver = create_session()
      sender = create_session()

      m1 = insert_dm(receiver.id, sender.id, "first")
      m2 = insert_dm(receiver.id, sender.id, "second")

      [first, second] = Messages.list_inbound_dms(receiver.id)
      assert first.id == m1.id
      assert second.id == m2.id
    end

    test "default limit is 20" do
      receiver = create_session()
      sender = create_session()

      for i <- 1..25, do: insert_dm(receiver.id, sender.id, "msg #{i}")

      dms = Messages.list_inbound_dms(receiver.id)
      assert length(dms) == 20
    end
  end
end
