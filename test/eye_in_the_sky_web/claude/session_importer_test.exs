defmodule EyeInTheSkyWeb.Claude.SessionImporterTest do
  use EyeInTheSkyWeb.DataCase, async: true

  alias EyeInTheSkyWeb.Claude.SessionImporter
  alias EyeInTheSkyWeb.{Messages, Sessions, Agents}

  setup do
    {:ok, agent} =
      Agents.create_agent(%{
        name: "test-agent",
        status: "stopped",
        provider: "claude"
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        status: "stopped",
        provider: "claude",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    %{session: session, agent: agent}
  end

  describe "import_messages/2" do
    test "imports user and assistant messages from raw JSONL format", %{session: session} do
      raw_messages = [
        %{
          "uuid" => "msg-user-001",
          "type" => "user",
          "timestamp" => "2026-03-20T12:00:00Z",
          "message" => %{
            "role" => "user",
            "content" => [%{"type" => "text", "text" => "Hello agent"}]
          }
        },
        %{
          "uuid" => "msg-asst-001",
          "type" => "assistant",
          "timestamp" => "2026-03-20T12:00:05Z",
          "message" => %{
            "role" => "assistant",
            "content" => [%{"type" => "text", "text" => "Hello human"}],
            "usage" => %{"input_tokens" => 100, "output_tokens" => 50}
          }
        }
      ]

      count = SessionImporter.import_messages(raw_messages, session.id)
      assert count == 2

      messages = Messages.list_messages_for_session(session.id)
      assert length(messages) == 2

      user_msg = Enum.find(messages, &(&1.sender_role == "user"))
      assert user_msg.body == "Hello agent"
      assert user_msg.source_uuid == "msg-user-001"
      assert user_msg.recipient_role == "agent"

      agent_msg = Enum.find(messages, &(&1.sender_role == "agent"))
      assert agent_msg.body == "Hello human"
      assert agent_msg.source_uuid == "msg-asst-001"
      assert agent_msg.recipient_role == "user"
    end

    test "skips messages without uuid", %{session: session} do
      raw_messages = [
        %{
          "uuid" => nil,
          "type" => "user",
          "timestamp" => "2026-03-20T12:00:00Z",
          "message" => %{
            "role" => "user",
            "content" => [%{"type" => "text", "text" => "No UUID"}]
          }
        }
      ]

      count = SessionImporter.import_messages(raw_messages, session.id)
      assert count == 0
    end

    test "parses ISO8601 timestamps correctly", %{session: session} do
      raw_messages = [
        %{
          "uuid" => "msg-ts-001",
          "type" => "assistant",
          "timestamp" => "2026-03-15T08:30:00Z",
          "message" => %{
            "role" => "assistant",
            "content" => [%{"type" => "text", "text" => "Timestamped message"}]
          }
        }
      ]

      SessionImporter.import_messages(raw_messages, session.id)

      [msg] = Messages.list_messages_for_session(session.id)
      assert msg.inserted_at == ~U[2026-03-15 08:30:00Z]
    end

    test "deduplicates against existing unlinked messages", %{session: session} do
      # Create an existing message without source_uuid (as if created by send_message)
      {:ok, _existing} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          session_id: session.id,
          sender_role: "user",
          recipient_role: "agent",
          direction: "outbound",
          body: "Hello agent",
          status: "delivered",
          provider: "claude"
        })

      raw_messages = [
        %{
          "uuid" => "msg-dedup-001",
          "type" => "user",
          "timestamp" => "2026-03-20T12:00:00Z",
          "message" => %{
            "role" => "user",
            "content" => [%{"type" => "text", "text" => "Hello agent"}]
          }
        }
      ]

      count = SessionImporter.import_messages(raw_messages, session.id)
      assert count == 1

      # Should still be just 1 message, not 2
      messages = Messages.list_messages_for_session(session.id)
      assert length(messages) == 1

      # The existing message should now have a source_uuid
      [msg] = messages
      assert msg.source_uuid == "msg-dedup-001"
    end

    test "maps user role to outbound direction, assistant to inbound", %{session: session} do
      raw_messages = [
        %{
          "uuid" => "msg-dir-user",
          "type" => "user",
          "timestamp" => "2026-03-20T12:00:00Z",
          "message" => %{
            "role" => "user",
            "content" => [%{"type" => "text", "text" => "User message"}]
          }
        },
        %{
          "uuid" => "msg-dir-asst",
          "type" => "assistant",
          "timestamp" => "2026-03-20T12:00:01Z",
          "message" => %{
            "role" => "assistant",
            "content" => [%{"type" => "text", "text" => "Assistant message"}]
          }
        }
      ]

      SessionImporter.import_messages(raw_messages, session.id)

      messages = Messages.list_messages_for_session(session.id)
      user_msg = Enum.find(messages, &(&1.sender_role == "user"))
      agent_msg = Enum.find(messages, &(&1.sender_role == "agent"))

      assert user_msg.direction == "outbound"
      assert agent_msg.direction == "inbound"
    end
  end
end
