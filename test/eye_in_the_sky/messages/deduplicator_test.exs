defmodule EyeInTheSky.Messages.DeduplicatorTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.{Agents, Messages, Sessions}
  alias EyeInTheSky.Messages.Deduplicator

  setup do
    {:ok, agent} =
      Agents.create_agent(%{name: "dedup-test-agent", status: "idle", provider: "claude"})

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

  defp base_attrs(session_id, source_uuid) do
    %{
      uuid: Ecto.UUID.generate(),
      source_uuid: source_uuid,
      session_id: session_id,
      sender_role: "agent",
      recipient_role: "user",
      provider: "claude",
      direction: "inbound",
      body: "Hello",
      status: "delivered"
    }
  end

  describe "find_or_create/2 with valid source_uuid" do
    test "inserts a new message when source_uuid is not yet stored", %{session: session} do
      uuid = Ecto.UUID.generate()
      attrs = base_attrs(session.id, uuid)

      assert {:ok, msg} = Deduplicator.find_or_create(attrs, %{})
      assert msg.source_uuid == uuid
      assert msg.body == "Hello"
    end

    test "returns existing message when source_uuid already stored", %{session: session} do
      uuid = Ecto.UUID.generate()
      attrs = base_attrs(session.id, uuid)

      {:ok, first} = Deduplicator.find_or_create(attrs, %{})
      {:ok, second} = Deduplicator.find_or_create(attrs, %{})

      assert first.id == second.id
    end

    test "enriches metadata on existing message when metadata is non-empty", %{session: session} do
      uuid = Ecto.UUID.generate()
      attrs = base_attrs(session.id, uuid)

      {:ok, _first} = Deduplicator.find_or_create(attrs, %{})
      metadata = %{duration_ms: 500, total_cost_usd: 0.001}
      {:ok, enriched} = Deduplicator.find_or_create(attrs, metadata)

      assert enriched.metadata[:duration_ms] == 500 or enriched.metadata["duration_ms"] == 500
    end
  end

  describe "find_or_create/2 with nil/missing source_uuid" do
    test "returns {:error, :source_uuid_required} when source_uuid is nil", %{session: session} do
      attrs = base_attrs(session.id, nil)
      assert {:error, :source_uuid_required} = Deduplicator.find_or_create(attrs, %{})
    end

    test "returns {:error, :source_uuid_required} when source_uuid key is missing", %{session: session} do
      attrs =
        base_attrs(session.id, "ignored")
        |> Map.delete(:source_uuid)

      assert {:error, :source_uuid_required} = Deduplicator.find_or_create(attrs, %{})
    end
  end

  describe "regression: repeated-body replies both persist" do
    test "two messages with identical body but different source_uuids are both stored", %{
      session: session
    } do
      body = "Done."

      attrs1 = %{base_attrs(session.id, Ecto.UUID.generate()) | body: body}
      attrs2 = %{base_attrs(session.id, Ecto.UUID.generate()) | body: body, uuid: Ecto.UUID.generate()}

      {:ok, msg1} = Deduplicator.find_or_create(attrs1, %{})
      {:ok, msg2} = Deduplicator.find_or_create(attrs2, %{})

      assert msg1.id != msg2.id
      assert msg1.body == body
      assert msg2.body == body

      count =
        Messages.list_messages_for_session(session.id)
        |> Enum.count(&(&1.body == body))

      assert count == 2
    end
  end
end
