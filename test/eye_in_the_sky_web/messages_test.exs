defmodule EyeInTheSkyWeb.MessagesTest do
  use EyeInTheSkyWeb.DataCase, async: true

  alias EyeInTheSkyWeb.{Agents, Messages, Sessions}

  defp uniq, do: System.unique_integer([:positive])

  defp create_session do
    {:ok, agent} = Agents.create_agent(%{name: "msg-test-agent-#{uniq()}", status: "active"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "idle"
      })

    session
  end

  defp insert_message(session_id, opts \\ []) do
    {:ok, msg} =
      Messages.create_message(%{
        uuid: Ecto.UUID.generate(),
        source_uuid: Keyword.get(opts, :source_uuid),
        session_id: session_id,
        sender_role: Keyword.get(opts, :sender_role, "agent"),
        recipient_role: "user",
        direction: "inbound",
        body: Keyword.get(opts, :body, "some response"),
        status: "delivered",
        provider: "claude",
        metadata: Keyword.get(opts, :metadata)
      })

    msg
  end

  # ---------------------------------------------------------------------------
  # total_tokens_for_session/1
  # ---------------------------------------------------------------------------

  describe "total_tokens_for_session/1" do
    test "returns 0 when session has no messages" do
      session = create_session()
      assert Messages.total_tokens_for_session(session.id) == 0
    end

    test "returns 0 when messages exist but none have usage metadata" do
      session = create_session()
      insert_message(session.id, body: "hello")
      insert_message(session.id, body: "world")
      assert Messages.total_tokens_for_session(session.id) == 0
    end

    test "returns 0 when metadata exists but has no usage key" do
      session = create_session()
      insert_message(session.id, metadata: %{stream_type: "result", total_cost_usd: 0.001})
      assert Messages.total_tokens_for_session(session.id) == 0
    end

    test "sums input and output tokens from a single message" do
      session = create_session()

      insert_message(session.id,
        metadata: %{"usage" => %{"input_tokens" => 100, "output_tokens" => 50}}
      )

      assert Messages.total_tokens_for_session(session.id) == 150
    end

    test "sums tokens across multiple messages" do
      session = create_session()

      insert_message(session.id,
        metadata: %{"usage" => %{"input_tokens" => 200, "output_tokens" => 80}}
      )

      insert_message(session.id,
        metadata: %{"usage" => %{"input_tokens" => 300, "output_tokens" => 120}}
      )

      assert Messages.total_tokens_for_session(session.id) == 700
    end

    test "ignores messages without usage metadata in a mixed set" do
      session = create_session()

      insert_message(session.id, body: "no metadata")
      insert_message(session.id, metadata: %{stream_type: "result"})

      insert_message(session.id,
        metadata: %{"usage" => %{"input_tokens" => 500, "output_tokens" => 200}}
      )

      assert Messages.total_tokens_for_session(session.id) == 700
    end

    test "does not count tokens from a different session" do
      s1 = create_session()
      s2 = create_session()

      insert_message(s1.id,
        metadata: %{"usage" => %{"input_tokens" => 100, "output_tokens" => 50}}
      )

      assert Messages.total_tokens_for_session(s2.id) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # record_incoming_reply/4 — metadata / token deduplication behaviour
  # ---------------------------------------------------------------------------

  describe "record_incoming_reply/4" do
    test "stores usage metadata on first insert" do
      session = create_session()
      usage = %{"input_tokens" => 400, "output_tokens" => 160}

      {:ok, msg} =
        Messages.record_incoming_reply(session.id, "claude", "done",
          metadata: %{"usage" => usage}
        )

      assert msg.metadata["usage"] == usage
      assert Messages.total_tokens_for_session(session.id) == 560
    end

    test "updates metadata when found by content (no source_uuid)" do
      # record_incoming_reply checks for a recent message with same body
      # and enriches it with metadata when source_uuid is nil.
      session = create_session()
      insert_message(session.id, sender_role: "agent", body: "done")

      usage = %{"input_tokens" => 200, "output_tokens" => 80}

      {:ok, _msg} =
        Messages.record_incoming_reply(session.id, "claude", "done",
          metadata: %{"usage" => usage}
        )

      assert Messages.total_tokens_for_session(session.id) == 280
    end

    test "updates metadata when found by source_uuid (sync-then-reply race)" do
      # Regression test for the sync-then-reply race that caused tokens to get stuck.
      #
      # Sequence:
      #   1. Session file sync imports message, assigns source_uuid from JSONL (no metadata)
      #   2. session_worker calls record_incoming_reply with same source_uuid + usage data
      #   3. record_incoming_reply finds the existing message and enriches its metadata
      #   4. Token count increases correctly
      session = create_session()
      source_uuid = Ecto.UUID.generate()

      # Step 1: session file sync creates the message with source_uuid but no metadata
      insert_message(session.id, source_uuid: source_uuid, body: "done")
      assert Messages.total_tokens_for_session(session.id) == 0

      # Step 2: session_worker calls record_incoming_reply with usage metadata
      usage = %{"input_tokens" => 500, "output_tokens" => 200}

      {:ok, msg} =
        Messages.record_incoming_reply(session.id, "claude", "done",
          source_uuid: source_uuid,
          metadata: %{"usage" => usage}
        )

      assert msg.metadata["usage"] == usage
      assert Messages.total_tokens_for_session(session.id) == 700
    end
  end
end
