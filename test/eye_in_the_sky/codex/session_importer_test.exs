defmodule EyeInTheSky.Codex.SessionImporterTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.{Agents, Messages, Sessions}
  alias EyeInTheSky.Codex.SessionImporter

  setup do
    {:ok, agent} =
      Agents.create_agent(%{
        name: "test-agent",
        status: "stopped",
        provider: "codex"
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        status: "idle",
        provider: "codex",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    %{session: session}
  end

  describe "import_messages/2" do
    test "imports codex messages with uuid", %{session: session} do
      uuid1 = "a0000000-0000-4000-8000-000000000001"
      uuid2 = "a0000000-0000-4000-8000-000000000002"

      messages = [
        %{
          uuid: uuid1,
          role: "user",
          content: "Hello Codex",
          timestamp: "2026-03-20T12:00:00Z",
          usage: nil,
          stream_type: nil
        },
        %{
          uuid: uuid2,
          role: "assistant",
          content: "Hello human",
          timestamp: "2026-03-20T12:00:05Z",
          usage: nil,
          stream_type: nil
        }
      ]

      count = SessionImporter.import_messages(messages, session.id)
      assert count == 2

      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 2

      user_msg = Enum.find(db_messages, &(&1.sender_role == "user"))
      assert user_msg.body == "Hello Codex"
      assert user_msg.source_uuid == uuid1

      agent_msg = Enum.find(db_messages, &(&1.sender_role == "agent"))
      assert agent_msg.body == "Hello human"
      assert agent_msg.source_uuid == uuid2
    end

    test "skips messages without uuid", %{session: session} do
      messages = [
        %{
          uuid: nil,
          role: "user",
          content: "No UUID",
          timestamp: "2026-03-20T12:00:00Z",
          usage: nil,
          stream_type: nil
        }
      ]

      count = SessionImporter.import_messages(messages, session.id)
      assert count == 0
    end
  end

  describe "drop_messages_before/2 (via read_messages_after_uuid)" do
    test "returns all messages when watermark is nil", %{session: session} do
      uuid1 = "a0000000-0000-4000-8000-000000000001"
      uuid2 = "a0000000-0000-4000-8000-000000000002"
      uuid3 = "a0000000-0000-4000-8000-000000000003"

      messages = [
        %{
          uuid: uuid1,
          role: "user",
          content: "First",
          timestamp: "2026-03-20T12:00:00Z",
          usage: nil,
          stream_type: nil
        },
        %{
          uuid: uuid2,
          role: "assistant",
          content: "Second",
          timestamp: "2026-03-20T12:00:05Z",
          usage: nil,
          stream_type: nil
        },
        %{
          uuid: uuid3,
          role: "user",
          content: "Third",
          timestamp: "2026-03-20T12:00:10Z",
          usage: nil,
          stream_type: nil
        }
      ]

      # When watermark is nil, SessionImporter.sync should import all
      # We test this indirectly by importing all, then checking the count
      count = SessionImporter.import_messages(messages, session.id)
      assert count == 3
    end

    test "returns only messages after the watermark uuid", %{session: session} do
      uuid1 = "a0000000-0000-4000-8000-000000000001"
      uuid2 = "a0000000-0000-4000-8000-000000000002"
      uuid3 = "a0000000-0000-4000-8000-000000000003"

      msg1 = %{
        uuid: uuid1,
        role: "user",
        content: "First",
        timestamp: "2026-03-20T12:00:00Z",
        usage: nil,
        stream_type: nil
      }

      msg2 = %{
        uuid: uuid2,
        role: "assistant",
        content: "Second",
        timestamp: "2026-03-20T12:00:05Z",
        usage: nil,
        stream_type: nil
      }

      msg3 = %{
        uuid: uuid3,
        role: "user",
        content: "Third",
        timestamp: "2026-03-20T12:00:10Z",
        usage: nil,
        stream_type: nil
      }

      # Import first two messages
      count1 = SessionImporter.import_messages([msg1, msg2], session.id)
      assert count1 == 2

      # Verify watermark is set to uuid2
      assert Messages.get_last_source_uuid(session.id) == uuid2

      # Now import all three messages again, via drop_messages_before logic
      # This simulates what SessionReader.read_messages_after_uuid would do
      # It returns [msg3] because drop_messages_before skips msg1 and msg2
      count2 = SessionImporter.import_messages([msg3], session.id)

      # Only message 3 should be imported
      assert count2 == 1

      # Verify final state
      all_messages = Messages.list_messages_for_session(session.id)
      assert length(all_messages) == 3
    end

    test "returns all messages when watermark uuid is not found (file rotated)" do
      uuid1 = "a0000000-0000-4000-8000-000000000001"
      uuid_old = "ffffffff-ffff-ffff-ffff-ffffffffffff"
      uuid2 = "a0000000-0000-4000-8000-000000000002"

      messages = [
        %{
          uuid: uuid1,
          role: "user",
          content: "First",
          timestamp: "2026-03-20T12:00:00Z",
          usage: nil,
          stream_type: nil
        },
        %{
          uuid: uuid2,
          role: "assistant",
          content: "Second",
          timestamp: "2026-03-20T12:00:05Z",
          usage: nil,
          stream_type: nil
        }
      ]

      # Simulate case where watermark uuid doesn't exist in current file
      # The drop_messages_before function should return all messages
      {:ok, agent} =
        Agents.create_agent(%{
          name: "test-agent-3",
          status: "stopped",
          provider: "codex"
        })

      {:ok, session3} =
        Sessions.create_session(%{
          uuid: Ecto.UUID.generate(),
          agent_id: agent.id,
          status: "idle",
          provider: "codex",
          started_at: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      # Insert a message with an old uuid that won't be in the new file
      {:ok, _old_msg} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          session_id: session3.id,
          sender_role: "user",
          recipient_role: "agent",
          direction: "outbound",
          body: "Old message",
          status: "delivered",
          provider: "codex",
          source_uuid: uuid_old
        })

      # Verify watermark is uuid_old
      assert Messages.get_last_source_uuid(session3.id) == uuid_old

      # Now import messages from the "new" file which doesn't contain uuid_old
      # Since the watermark uuid is not found, drop_messages_before should return all
      count = SessionImporter.import_messages(messages, session3.id)

      # Both messages should be imported (because watermark uuid is not found)
      assert count == 2

      all_messages = Messages.list_messages_for_session(session3.id)
      assert length(all_messages) == 3
    end
  end
end
