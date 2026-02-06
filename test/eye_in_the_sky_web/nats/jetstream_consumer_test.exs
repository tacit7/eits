defmodule EyeInTheSkyWeb.NATS.JetStreamConsumerTest do
  use EyeInTheSkyWeb.DataCase

  alias EyeInTheSkyWeb.NATS.JetStreamConsumer
  alias EyeInTheSkyWeb.Messages

  setup do
    # Ensure tables exist that messages FK references
    # (these come from core schema, not Ecto migrations)
    Ecto.Adapters.SQL.query!(EyeInTheSkyWeb.Repo, """
    CREATE TABLE IF NOT EXISTS projects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      slug TEXT,
      path TEXT,
      active BOOLEAN DEFAULT 1,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
    """)

    Ecto.Adapters.SQL.query!(EyeInTheSkyWeb.Repo, """
    CREATE TABLE IF NOT EXISTS channels (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      channel_type TEXT DEFAULT 'public',
      project_id INTEGER REFERENCES projects(id),
      inserted_at TEXT,
      updated_at TEXT
    )
    """)

    # Insert test channels used by v2 message tests
    Ecto.Adapters.SQL.query!(EyeInTheSkyWeb.Repo,
      "INSERT OR IGNORE INTO channels (id, name, inserted_at, updated_at) VALUES (?1, ?2, ?3, ?3)",
      ["ch-001", "test-channel-1", DateTime.to_iso8601(DateTime.utc_now())]
    )

    Ecto.Adapters.SQL.query!(EyeInTheSkyWeb.Repo,
      "INSERT OR IGNORE INTO channels (id, name, inserted_at, updated_at) VALUES (?1, ?2, ?3, ?3)",
      ["ch-002", "test-channel-2", DateTime.to_iso8601(DateTime.utc_now())]
    )

    :ok
  end

  describe "decode_body/1" do
    test "decodes raw JSON string" do
      json = Jason.encode!(%{"op" => "msg", "body" => "hello"})
      assert {:ok, %{"op" => "msg", "body" => "hello"}} = JetStreamConsumer.decode_body(json)
    end

    test "decodes base64-encoded JSON" do
      json = Jason.encode!(%{"op" => "msg", "body" => "hello"})
      b64 = Base.encode64(json)
      assert {:ok, %{"op" => "msg", "body" => "hello"}} = JetStreamConsumer.decode_body(b64)
    end

    test "returns error for non-binary input" do
      assert {:error, :not_binary} = JetStreamConsumer.decode_body(123)
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = JetStreamConsumer.decode_body("not json at all {{{")
    end
  end

  describe "compute_dedup_id/4" do
    test "uses explicit message_id from meta" do
      envelope = %{"meta" => %{"message_id" => "abc-123"}}
      assert "abc-123" = JetStreamConsumer.compute_dedup_id(envelope, "s1", "r1", "body")
    end

    test "uses top-level message_id" do
      envelope = %{"message_id" => "def-456"}
      assert "def-456" = JetStreamConsumer.compute_dedup_id(envelope, "s1", "r1", "body")
    end

    test "uses top-level id" do
      envelope = %{"id" => "ghi-789"}
      assert "ghi-789" = JetStreamConsumer.compute_dedup_id(envelope, "s1", "r1", "body")
    end

    test "computes SHA256 hash when no explicit ID" do
      envelope = %{"some" => "data"}
      id = JetStreamConsumer.compute_dedup_id(envelope, "sender1", "receiver1", "hello")

      # Should be 36 chars hex
      assert String.length(id) == 36
      assert Regex.match?(~r/^[a-f0-9]{36}$/, id)
    end

    test "same inputs produce same dedup ID" do
      envelope = %{}
      id1 = JetStreamConsumer.compute_dedup_id(envelope, "s1", "r1", "body")
      id2 = JetStreamConsumer.compute_dedup_id(envelope, "s1", "r1", "body")
      assert id1 == id2
    end

    test "different inputs produce different dedup IDs" do
      envelope = %{}
      id1 = JetStreamConsumer.compute_dedup_id(envelope, "s1", "r1", "body1")
      id2 = JetStreamConsumer.compute_dedup_id(envelope, "s1", "r1", "body2")
      assert id1 != id2
    end
  end

  describe "process_decoded/2 with v2 channel messages" do
    test "creates v2 channel message in database" do
      envelope = %{
        "op" => "msg",
        "channel" => "chat",
        "version" => "eits-messaging-v2",
        "channel_id" => "ch-001",
        "msg" => "Hello channel",
        "meta" => %{
          "message_id" => "v2-msg-#{System.unique_integer([:positive])}",
          "sender_session_id" => "sess-001",
          "provider" => "claude"
        }
      }

      JetStreamConsumer.process_decoded(envelope, "events.chat")

      msg_id = get_in(envelope, ["meta", "message_id"])
      assert Messages.message_exists?(msg_id)
    end

    test "skips duplicate v2 channel message" do
      msg_id = "v2-dedup-#{System.unique_integer([:positive])}"

      envelope = %{
        "op" => "msg",
        "channel" => "chat",
        "version" => "eits-messaging-v2",
        "channel_id" => "ch-002",
        "msg" => "Hello again",
        "meta" => %{
          "message_id" => msg_id,
          "sender_session_id" => "sess-002",
          "provider" => "claude"
        }
      }

      # First call creates the message
      JetStreamConsumer.process_decoded(envelope, "events.chat")
      assert Messages.message_exists?(msg_id)

      # Second call should skip (no error, no duplicate)
      JetStreamConsumer.process_decoded(envelope, "events.chat")

      # Should still be exactly one message with this ID
      msg = Messages.get_message!(msg_id)
      assert msg.body == "Hello again"
    end
  end

  describe "process_decoded/2 with v1 session messages" do
    test "creates v1 session message in database" do
      envelope = %{
        "op" => "msg",
        "channel" => "chat",
        "reply_to" => "sess-v1-001",
        "msg" => "Hello v1",
        "meta" => %{
          "provider" => "nats"
        }
      }

      JetStreamConsumer.process_decoded(envelope, "events.chat")

      # Message should exist (auto-generated ID via record_incoming_reply)
      messages = Messages.list_messages_for_session("sess-v1-001")
      assert length(messages) >= 1
      assert Enum.any?(messages, fn m -> m.body == "Hello v1" end)
    end
  end

  describe "process_decoded/2 with DM messages" do
    test "creates DM message for receiver" do
      data = %{
        "receiver_id" => "dm-receiver-001",
        "sender_id" => "dm-sender-001",
        "message" => "Direct message test"
      }

      JetStreamConsumer.process_decoded(data, "events.dm")

      messages = Messages.list_messages_for_session("dm-receiver-001")
      assert length(messages) >= 1
      assert Enum.any?(messages, fn m -> String.contains?(m.body, "Direct message test") end)
    end

    test "deduplicates DM messages" do
      data = %{
        "receiver_id" => "dm-dedup-recv",
        "sender_id" => "dm-dedup-send",
        "message" => "Dedup DM test"
      }

      # Send same message twice
      JetStreamConsumer.process_decoded(data, "events.dm")
      JetStreamConsumer.process_decoded(data, "events.dm")

      messages = Messages.list_messages_for_session("dm-dedup-recv")
      dm_messages = Enum.filter(messages, fn m -> String.contains?(m.body, "Dedup DM test") end)
      assert length(dm_messages) == 1
    end

    test "ignores messages without receiver_id" do
      data = %{
        "sender_id" => "orphan-sender",
        "message" => "No receiver"
      }

      # Should not crash
      JetStreamConsumer.process_decoded(data, "events.dm")
    end
  end
end
