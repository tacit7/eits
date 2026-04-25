defmodule EyeInTheSky.Messages.BulkImporterTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.{Agents, Messages, Sessions}
  alias EyeInTheSky.Messages.BulkImporter
  alias EyeInTheSky.Repo

  setup do
    {:ok, agent} =
      Agents.create_agent(%{name: "test-agent", status: "idle", provider: "claude"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        status: "idle",
        provider: "claude",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    %{session: session}
  end

  describe "import_messages/3" do
    test "imports messages with the given provider", %{session: session} do
      messages = [
        %{uuid: Ecto.UUID.generate(), role: "user", content: "Hello", timestamp: nil, usage: nil},
        %{
          uuid: Ecto.UUID.generate(),
          role: "assistant",
          content: "Hi",
          timestamp: nil,
          usage: nil
        }
      ]

      count = BulkImporter.import_messages(messages, session.id, provider: "codex")
      assert count == 2

      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 2
      assert Enum.all?(db_messages, &(&1.provider == "codex"))
    end

    test "skips messages without uuid", %{session: session} do
      messages = [
        %{uuid: nil, role: "user", content: "No UUID", timestamp: nil, usage: nil}
      ]

      count = BulkImporter.import_messages(messages, session.id, provider: "claude")
      assert count == 0
    end

    test "applies metadata_fn when provided", %{session: session} do
      messages = [
        %{
          uuid: Ecto.UUID.generate(),
          role: "assistant",
          content: "With usage",
          timestamp: nil,
          usage: %{"input_tokens" => 10}
        }
      ]

      metadata_fn = fn msg ->
        if msg.usage, do: %{"usage" => msg.usage}, else: nil
      end

      count =
        BulkImporter.import_messages(messages, session.id,
          provider: "claude",
          metadata_fn: metadata_fn
        )

      assert count == 1

      [msg] = Messages.list_messages_for_session(session.id)
      assert msg.metadata == %{"usage" => %{"input_tokens" => 10}}
    end

    test "deduplicates against existing unlinked messages", %{session: session} do
      {:ok, _existing} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          session_id: session.id,
          sender_role: "user",
          recipient_role: "agent",
          direction: "outbound",
          body: "Hello",
          status: "delivered",
          provider: "codex"
        })

      source_uuid = Ecto.UUID.generate()

      messages = [
        %{uuid: source_uuid, role: "user", content: "Hello", timestamp: nil, usage: nil}
      ]

      count = BulkImporter.import_messages(messages, session.id, provider: "codex")
      assert count == 1

      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 1
      assert hd(db_messages).source_uuid == source_uuid
    end

    test "parses ISO8601 timestamps", %{session: session} do
      messages = [
        %{
          uuid: Ecto.UUID.generate(),
          role: "user",
          content: "Timed",
          timestamp: "2026-03-15T08:30:00Z",
          usage: nil
        }
      ]

      BulkImporter.import_messages(messages, session.id, provider: "codex")

      [msg] = Messages.list_messages_for_session(session.id)
      assert msg.inserted_at == ~U[2026-03-15 08:30:00Z]
    end

    test "maps user role to outbound, assistant to inbound", %{session: session} do
      messages = [
        %{uuid: Ecto.UUID.generate(), role: "user", content: "Out", timestamp: nil, usage: nil},
        %{
          uuid: Ecto.UUID.generate(),
          role: "assistant",
          content: "In",
          timestamp: nil,
          usage: nil
        }
      ]

      BulkImporter.import_messages(messages, session.id, provider: "codex")

      db_messages = Messages.list_messages_for_session(session.id)
      user_msg = Enum.find(db_messages, &(&1.sender_role == "user"))
      agent_msg = Enum.find(db_messages, &(&1.sender_role == "agent"))

      assert user_msg.direction == "outbound"
      assert agent_msg.direction == "inbound"
    end

    test "skips existing_source_uuids fast-path (source_uuid already in DB)", %{session: session} do
      source_uuid = Ecto.UUID.generate()

      # First import: message with source_uuid is created
      messages1 = [
        %{uuid: source_uuid, role: "user", content: "Hello", timestamp: nil, usage: nil}
      ]

      count1 = BulkImporter.import_messages(messages1, session.id, provider: "codex")
      assert count1 == 1

      db_messages1 = Messages.list_messages_for_session(session.id)
      assert length(db_messages1) == 1
      assert hd(db_messages1).source_uuid == source_uuid

      # Second import: same source_uuid should be skipped by fast-path
      messages2 = [
        %{uuid: source_uuid, role: "user", content: "Hello", timestamp: nil, usage: nil}
      ]

      count2 = BulkImporter.import_messages(messages2, session.id, provider: "codex")
      assert count2 == 1  # counted as processed, but not inserted (fast-path returns true)

      db_messages2 = Messages.list_messages_for_session(session.id)
      assert length(db_messages2) == 1  # no duplicate created
    end

    test "skips dm_already_recorded? path (user msg matches recent inbound DM body)", %{
      session: session
    } do
      # Create an inbound DM (agent role) with a specific body
      {:ok, _inbound_dm} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          session_id: session.id,
          sender_role: "agent",
          recipient_role: "user",
          direction: "inbound",
          body: "DM from agent",
          status: "delivered",
          provider: "codex"
        })

      # Now try to import a user-role message with the same body
      # This should be skipped because dm_already_recorded? detects the inbound DM
      source_uuid = Ecto.UUID.generate()

      messages = [
        %{uuid: source_uuid, role: "user", content: "DM from agent", timestamp: nil, usage: nil}
      ]

      count = BulkImporter.import_messages(messages, session.id, provider: "codex")
      assert count == 1  # counted as processed, but skipped by dm_already_recorded?

      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 1  # only the inbound DM exists
      assert hd(db_messages).sender_role == "agent"
    end

    test "importing_from_file?: true uses 86400s window — dedupes a DM from 2 hours ago", %{
      session: session
    } do
      two_hours_ago =
        DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.truncate(:second)

      {:ok, _inbound_dm} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          session_id: session.id,
          sender_role: "agent",
          recipient_role: "user",
          direction: "inbound",
          body: "old DM body",
          status: "delivered",
          provider: "codex",
          inserted_at: two_hours_ago,
          updated_at: two_hours_ago
        })

      messages = [
        %{uuid: Ecto.UUID.generate(), role: "user", content: "old DM body", timestamp: nil, usage: nil}
      ]

      count =
        BulkImporter.import_messages(messages, session.id,
          provider: "codex",
          importing_from_file?: true
        )

      # Deduped — only the original inbound DM exists
      assert count == 1
      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 1
      assert hd(db_messages).sender_role == "agent"
    end

    test "importing_from_file?: false uses 60s window — does NOT dedupe a DM from 2 hours ago", %{
      session: session
    } do
      two_hours_ago =
        DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.truncate(:second)

      {:ok, _inbound_dm} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          session_id: session.id,
          sender_role: "agent",
          recipient_role: "user",
          direction: "inbound",
          body: "old DM body",
          status: "delivered",
          provider: "codex",
          inserted_at: two_hours_ago,
          updated_at: two_hours_ago
        })

      source_uuid = Ecto.UUID.generate()

      messages = [
        %{uuid: source_uuid, role: "user", content: "old DM body", timestamp: nil, usage: nil}
      ]

      count = BulkImporter.import_messages(messages, session.id, provider: "codex")

      # NOT deduped — 60s window doesn't reach 2 hours ago, so the message is inserted
      assert count == 1
      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 2
      user_msg = Enum.find(db_messages, &(&1.sender_role == "user"))
      assert user_msg.source_uuid == source_uuid
    end

    test "importing_from_file?: false uses 60s window — dedupes a DM from 10 seconds ago", %{
      session: session
    } do
      ten_seconds_ago =
        DateTime.utc_now() |> DateTime.add(-10, :second) |> DateTime.truncate(:second)

      {:ok, _inbound_dm} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          session_id: session.id,
          sender_role: "agent",
          recipient_role: "user",
          direction: "inbound",
          body: "recent DM body",
          status: "delivered",
          provider: "codex",
          inserted_at: ten_seconds_ago,
          updated_at: ten_seconds_ago
        })

      messages = [
        %{uuid: Ecto.UUID.generate(), role: "user", content: "recent DM body", timestamp: nil, usage: nil}
      ]

      count = BulkImporter.import_messages(messages, session.id, provider: "codex")

      # Deduped — 10s ago is within the 60s window
      assert count == 1
      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 1
      assert hd(db_messages).sender_role == "agent"
    end

    # ---------------------------------------------------------------------------
    # agent_reply_already_recorded? guard — SDK UUID vs JSONL UUID dedup
    # ---------------------------------------------------------------------------

    test "skips agent reply already persisted by AgentWorker (within 30s window)", %{
      session: session
    } do
      # Simulate AgentWorker storing the reply with the SDK result UUID
      sdk_uuid = Ecto.UUID.generate()

      {:ok, _existing} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          source_uuid: sdk_uuid,
          session_id: session.id,
          sender_role: "agent",
          recipient_role: "user",
          direction: "inbound",
          body: "The final answer is 42.",
          status: "delivered",
          provider: "claude"
        })

      # BulkImporter now runs with the JSONL UUID — different from the SDK UUID
      jsonl_uuid = Ecto.UUID.generate()

      messages = [
        %{uuid: jsonl_uuid, role: "assistant", content: "The final answer is 42.", timestamp: nil, usage: nil}
      ]

      count = BulkImporter.import_messages(messages, session.id, provider: "claude")

      # Deduped — body matches within 30s; only the AgentWorker-persisted record exists
      assert count == 1
      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 1
      assert hd(db_messages).source_uuid == sdk_uuid
    end

    test "does NOT skip agent reply persisted more than 30s ago (outside dedup window)", %{
      session: session
    } do
      sixty_seconds_ago =
        DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      {:ok, _old_msg} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          source_uuid: Ecto.UUID.generate(),
          session_id: session.id,
          sender_role: "agent",
          recipient_role: "user",
          direction: "inbound",
          body: "Earlier reply.",
          status: "delivered",
          provider: "claude",
          inserted_at: sixty_seconds_ago,
          updated_at: sixty_seconds_ago
        })

      jsonl_uuid = Ecto.UUID.generate()

      messages = [
        %{uuid: jsonl_uuid, role: "assistant", content: "Earlier reply.", timestamp: nil, usage: nil}
      ]

      count = BulkImporter.import_messages(messages, session.id, provider: "claude")

      # NOT deduped — 60s is outside the 30s window, so BulkImporter inserts a new row
      assert count == 1
      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 2
      new_msg = Enum.find(db_messages, &(&1.source_uuid == jsonl_uuid))
      assert new_msg != nil
    end

    test "agent reply within 30s is skipped even when importing_from_file?: true", %{
      session: session
    } do
      sdk_uuid = Ecto.UUID.generate()

      {:ok, _existing} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          source_uuid: sdk_uuid,
          session_id: session.id,
          sender_role: "agent",
          recipient_role: "user",
          direction: "inbound",
          body: "Some agent output.",
          status: "delivered",
          provider: "claude"
        })

      jsonl_uuid = Ecto.UUID.generate()

      messages = [
        %{uuid: jsonl_uuid, role: "assistant", content: "Some agent output.", timestamp: nil, usage: nil}
      ]

      count =
        BulkImporter.import_messages(messages, session.id,
          provider: "claude",
          importing_from_file?: true
        )

      # Guard fires regardless of importing_from_file? — deduped to the existing record
      assert count == 1
      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 1
      assert hd(db_messages).source_uuid == sdk_uuid
    end

    # ---------------------------------------------------------------------------
    # In-batch dedup — MapSet guard catches duplicates within the same reduce
    # ---------------------------------------------------------------------------

    test "in-batch dedup: 3 assistant messages with same body and different uuids → 1 row",
         %{session: session} do
      body = "Batch duplicate body"

      messages = [
        %{uuid: Ecto.UUID.generate(), role: "assistant", content: body, timestamp: nil, usage: nil},
        %{uuid: Ecto.UUID.generate(), role: "assistant", content: body, timestamp: nil, usage: nil},
        %{uuid: Ecto.UUID.generate(), role: "assistant", content: body, timestamp: nil, usage: nil}
      ]

      count = BulkImporter.import_messages(messages, session.id, provider: "claude")

      # Only the first is inserted; the other two are caught by the MapSet.
      assert count == 3
      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 1
    end

    test "mixed dedup: existing DB row + 2 in-batch messages with same body → 1 row",
         %{session: session} do
      body = "Mixed dedup body"
      sdk_uuid = Ecto.UUID.generate()

      {:ok, _existing} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          source_uuid: sdk_uuid,
          session_id: session.id,
          sender_role: "agent",
          recipient_role: "user",
          direction: "inbound",
          body: body,
          status: "delivered",
          provider: "claude"
        })

      messages = [
        %{uuid: Ecto.UUID.generate(), role: "assistant", content: body, timestamp: nil, usage: nil},
        %{uuid: Ecto.UUID.generate(), role: "assistant", content: body, timestamp: nil, usage: nil}
      ]

      count = BulkImporter.import_messages(messages, session.id, provider: "claude")

      assert count == 2
      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 1
      assert hd(db_messages).source_uuid == sdk_uuid
    end

    test "user messages with same body in same batch are NOT deduped (both persist)", %{
      session: session
    } do
      body = "Same user question"

      messages = [
        %{uuid: Ecto.UUID.generate(), role: "user", content: body, timestamp: nil, usage: nil},
        %{uuid: Ecto.UUID.generate(), role: "user", content: body, timestamp: nil, usage: nil}
      ]

      count = BulkImporter.import_messages(messages, session.id, provider: "claude")

      assert count == 2
      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 2
      assert Enum.all?(db_messages, &(&1.sender_role == "user"))
    end

    test "regression: record_incoming_reply + BulkImporter with importing_from_file?: true yields one row",
         %{session: session} do
      sdk_uuid = Ecto.UUID.generate()

      # Simulate AgentWorker calling record_incoming_reply (SDK result UUID as source_uuid)
      {:ok, _sdk_row} =
        Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          source_uuid: sdk_uuid,
          session_id: session.id,
          sender_role: "agent",
          recipient_role: "user",
          direction: "inbound",
          body: "Hello from agent.",
          status: "delivered",
          provider: "claude"
        })

      # BulkImporter runs from session file sync — different (JSONL) uuid, same body
      jsonl_uuid = Ecto.UUID.generate()

      messages = [
        %{uuid: jsonl_uuid, role: "assistant", content: "Hello from agent.", timestamp: nil, usage: nil}
      ]

      count =
        BulkImporter.import_messages(messages, session.id,
          provider: "claude",
          importing_from_file?: true
        )

      assert count == 1
      db_messages = Messages.list_messages_for_session(session.id)
      assert length(db_messages) == 1
      assert hd(db_messages).source_uuid == sdk_uuid
    end
  end

  describe "run_inserts/1 telemetry" do
    test "emits :constraint_violation telemetry and returns 0 on FK violation" do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:eits, :messages, :bulk_import, :constraint_violation]
        ])

      msgs = [
        %{uuid: Ecto.UUID.generate(), role: "user", content: "hi", timestamp: nil, usage: nil}
      ]

      # session_id 999_999_999 does not exist — causes foreign_key_violation on INSERT
      count = BulkImporter.import_messages(msgs, 999_999_999, provider: "test")

      assert count == 0

      assert_received {[:eits, :messages, :bulk_import, :constraint_violation], ^ref,
                       %{batch_size: 1}, %{code: :foreign_key_violation, table: "messages"}}
    end

    test "emits :failed telemetry and reraises on systemic DB error", %{session: session} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:eits, :messages, :bulk_import, :failed]
        ])

      # Use a BEFORE INSERT trigger that raises a non-constraint Postgres error.
      # DDL is transactional in Postgres — this is visible only to this connection's
      # transaction and rolled back automatically at test cleanup.
      # XX000 (internal_error) is not in @constraint_codes, so it routes to the systemic path.
      suffix = :erlang.unique_integer([:positive])
      fn_name = "test_raise_systemic_#{suffix}"
      trig_name = "test_block_insert_#{suffix}"

      Repo.query!("""
      CREATE FUNCTION #{fn_name}() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'Simulated systemic error' USING ERRCODE = 'XX000';
      END;
      $$
      """)

      Repo.query!("""
      CREATE TRIGGER #{trig_name} BEFORE INSERT ON messages
      FOR EACH ROW EXECUTE FUNCTION #{fn_name}()
      """)

      msgs = [
        %{uuid: Ecto.UUID.generate(), role: "user", content: "hi", timestamp: nil, usage: nil}
      ]

      assert_raise Postgrex.Error, fn ->
        BulkImporter.import_messages(msgs, session.id, provider: "test")
      end

      assert_received {[:eits, :messages, :bulk_import, :failed], ^ref, %{batch_size: 1},
                       %{table: "messages"}}
    end
  end
end
