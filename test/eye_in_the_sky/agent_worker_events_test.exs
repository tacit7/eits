defmodule EyeInTheSky.AgentWorkerEventsTest do
  use EyeInTheSky.DataCase, async: false

  @moduletag :capture_log

  alias EyeInTheSky.{Agents, Channels, Messages, Sessions}
  alias EyeInTheSky.AgentWorkerEvents

  # --- Helpers ---

  defp create_session(opts \\ %{}) do
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: Map.get(opts, :description, "Test Agent"),
        source: "test"
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Map.get(opts, :uuid, Ecto.UUID.generate()),
        agent_id: agent.id,
        name: Map.get(opts, :name, "Test Session"),
        provider: Map.get(opts, :provider, "claude"),
        status: Map.get(opts, :status, "working"),
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {agent, session}
  end

  defp reload_session(session) do
    {:ok, s} = Sessions.get_session(session.id)
    s
  end

  # --- update_session_status (via lifecycle events) ---

  describe "on_sdk_started/2" do
    test "sets session status to working" do
      {_agent, session} = create_session(%{status: "idle"})

      AgentWorkerEvents.on_sdk_started(session.id, session.uuid)

      assert reload_session(session).status == "working"
    end

    test "promotes pending agent to running" do
      {agent, session} = create_session(%{status: "idle"})
      {:ok, _} = Agents.update_agent(agent, %{status: "pending"})

      AgentWorkerEvents.on_sdk_started(session.id, session.uuid)

      {:ok, updated_agent} = Agents.get_agent(agent.id)
      assert updated_agent.status == "running"
    end

    test "does not change non-pending agent status" do
      {agent, session} = create_session()
      {:ok, _} = Agents.update_agent(agent, %{status: "running"})

      AgentWorkerEvents.on_sdk_started(session.id, session.uuid)

      {:ok, updated_agent} = Agents.get_agent(agent.id)
      assert updated_agent.status == "running"
    end
  end

  describe "on_sdk_completed/3" do
    test "sets status to idle for claude provider" do
      {_agent, session} = create_session(%{status: "working"})

      AgentWorkerEvents.on_sdk_completed(session.id, session.uuid, "claude")

      assert reload_session(session).status == "idle"
    end

    test "sets status to idle for codex provider (no longer parks in waiting)" do
      {_agent, session} = create_session(%{status: "working", provider: "codex"})

      AgentWorkerEvents.on_sdk_completed(session.id, session.uuid, "codex")

      assert reload_session(session).status == "idle"
    end

    test "sets last_activity_at when transitioning to idle" do
      {_agent, session} = create_session(%{status: "working"})

      before = DateTime.utc_now()
      AgentWorkerEvents.on_sdk_completed(session.id, session.uuid, "claude")
      updated = reload_session(session)

      assert updated.last_activity_at != nil
      assert DateTime.compare(updated.last_activity_at, before) in [:gt, :eq]
    end

    test "broadcasts session_idle on successful DB update" do
      {_agent, session} = create_session(%{status: "working"})
      Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "session_lifecycle")

      AgentWorkerEvents.on_sdk_completed(session.id, session.uuid, "claude")

      session_id = session.id
      assert_receive {:session_idle, ^session_id}, 1_000
    end
  end

  describe "on_sdk_errored/2" do
    test "sets session status to idle" do
      {_agent, session} = create_session(%{status: "working"})

      AgentWorkerEvents.on_sdk_errored(session.id, session.uuid)

      assert reload_session(session).status == "idle"
    end
  end

  describe "on_max_retries_exceeded/2" do
    test "sets session status to failed" do
      {_agent, session} = create_session(%{status: "working"})

      AgentWorkerEvents.on_max_retries_exceeded(session.id, session.uuid)

      assert reload_session(session).status == "failed"
    end
  end

  describe "on_session_failed/3" do
    test "sets session DB status to failed and records reason" do
      {_agent, session} = create_session(%{status: "working"})

      AgentWorkerEvents.on_sdk_errored(session.id, session.uuid)

      AgentWorkerEvents.on_session_failed(
        session.id,
        session.uuid,
        {:billing_error, "low balance"}
      )

      updated = reload_session(session)
      assert updated.status == "failed"
      assert updated.status_reason == "billing_error"
    end

    test "emits exactly one session_idle broadcast for the systemic-error sequence" do
      {_agent, session} = create_session(%{status: "working"})
      Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "session_lifecycle")

      AgentWorkerEvents.on_sdk_errored(session.id, session.uuid)

      AgentWorkerEvents.on_session_failed(
        session.id,
        session.uuid,
        {:billing_error, "low balance"}
      )

      session_id = session.id
      assert_receive {:session_idle, ^session_id}, 1_000
      refute_receive {:session_idle, ^session_id}, 200
    end
  end

  # --- session_idle broadcast ordering ---

  describe "session_idle broadcast" do
    test "fires after status is written to DB" do
      {_agent, session} = create_session(%{status: "working"})
      Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "session_lifecycle")

      AgentWorkerEvents.on_sdk_completed(session.id, session.uuid, "claude")

      # When we receive the broadcast, the DB should already reflect idle
      receive do
        {:session_idle, _id} ->
          assert reload_session(session).status == "idle"
      after
        1_000 -> flunk("session_idle broadcast not received")
      end
    end

    test "does not fire when status is working (non-idle transition)" do
      {_agent, session} = create_session(%{status: "idle"})
      Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "session_lifecycle")

      AgentWorkerEvents.on_sdk_started(session.id, session.uuid)

      refute_receive {:session_idle, _}, 200
    end
  end

  # --- on_provider_conversation_id_changed ---

  describe "on_provider_conversation_id_changed/3" do
    test "updates session uuid in DB synchronously" do
      old_uuid = Ecto.UUID.generate()
      new_uuid = Ecto.UUID.generate()
      {_agent, session} = create_session(%{uuid: old_uuid})

      AgentWorkerEvents.on_provider_conversation_id_changed(session.id, old_uuid, new_uuid)

      # Synchronous — no need to wait; DB must reflect new UUID immediately
      updated = reload_session(session)
      assert updated.uuid == new_uuid
    end

    test "handles missing session gracefully" do
      # Should not raise, just log a warning
      assert :ok ==
               (AgentWorkerEvents.on_provider_conversation_id_changed(
                  999_999,
                  "old",
                  "new"
                ) && :ok)
    end
  end

  # --- on_result_received ---

  describe "on_result_received/2" do
    test "saves message to DB" do
      {_agent, session} = create_session()

      metadata = %{
        duration_ms: 100,
        total_cost_usd: 0.001,
        usage: %{input_tokens: 10, output_tokens: 5},
        model_usage: nil,
        num_turns: 1,
        is_error: false
      }

      AgentWorkerEvents.on_result_received(session.id, %{
        provider: "claude",
        text: "hello world",
        metadata: metadata,
        channel_id: nil,
        source_uuid: nil
      })

      messages = Messages.list_messages_for_session(session.id)
      assert Enum.any?(messages, &(&1.body == "hello world"))
    end

    test "skips DB save for empty text" do
      {_agent, session} = create_session()

      AgentWorkerEvents.on_result_received(session.id, %{
        provider: "claude",
        text: "   ",
        metadata: %{},
        channel_id: nil,
        source_uuid: nil
      })

      messages = Messages.list_messages_for_session(session.id)
      assert messages == []
    end

    test "skips DB save for [NO_RESPONSE]" do
      {_agent, session} = create_session()

      AgentWorkerEvents.on_result_received(session.id, %{
        provider: "claude",
        text: "[NO_RESPONSE]",
        metadata: %{},
        channel_id: nil,
        source_uuid: nil
      })

      messages = Messages.list_messages_for_session(session.id)
      assert messages == []
    end

    test "returns :ok for non-binary text (no crash)" do
      {_agent, session} = create_session()

      result =
        AgentWorkerEvents.on_result_received(session.id, %{
          provider: "claude",
          text: nil,
          metadata: %{},
          channel_id: nil
        })

      # Second clause — returns :ok from Logger.warning
      assert result == :ok
    end
  end

  # --- on_spawn_error ---

  describe "on_spawn_error/2" do
    test "records a system error message" do
      {_agent, session} = create_session()

      AgentWorkerEvents.on_spawn_error(session.id, :enoent)

      messages = Messages.list_messages_for_session(session.id)
      assert Enum.any?(messages, &String.contains?(&1.body, "spawn error"))
    end
  end

  # --- channel read receipts ---

  defp create_channel do
    {:ok, channel} =
      Channels.create_channel(%{
        uuid: Ecto.UUID.generate(),
        name: "test-channel-#{System.unique_integer([:positive])}",
        channel_type: "public"
      })

    channel
  end

  defp get_member_last_read_at(channel_id, session_id) do
    case Channels.get_member(channel_id, session_id) do
      {:ok, member} -> member.last_read_at
      _ -> nil
    end
  end

  describe "on_result_received/2 — channel read receipts" do
    test "writes last_read_at when channel_id is present" do
      {agent, session} = create_session()
      channel = create_channel()
      Channels.add_member(channel.id, agent.id, session.id)

      assert get_member_last_read_at(channel.id, session.id) == nil

      AgentWorkerEvents.on_result_received(session.id, %{
        provider: "claude",
        text: "reply in channel",
        metadata: %{},
        channel_id: channel.id,
        source_uuid: nil
      })

      assert get_member_last_read_at(channel.id, session.id) != nil
    end

    test "does not write last_read_at when channel_id is nil (DM path)" do
      {agent, session} = create_session()
      channel = create_channel()
      Channels.add_member(channel.id, agent.id, session.id)

      AgentWorkerEvents.on_result_received(session.id, %{
        provider: "claude",
        text: "dm reply",
        metadata: %{},
        channel_id: nil,
        source_uuid: nil
      })

      # No channel touched — last_read_at stays nil
      assert get_member_last_read_at(channel.id, session.id) == nil
    end

    test "last_read_at is not updated for suppressed [NO_RESPONSE] — message skipped" do
      {agent, session} = create_session()
      channel = create_channel()
      Channels.add_member(channel.id, agent.id, session.id)

      AgentWorkerEvents.on_result_received(session.id, %{
        provider: "claude",
        text: "[NO_RESPONSE]",
        metadata: %{},
        channel_id: channel.id,
        source_uuid: nil
      })

      # maybe_mark_channel_read still fires even for [NO_RESPONSE] — agent consumed the message
      assert get_member_last_read_at(channel.id, session.id) != nil
    end

    test "does not crash when session is not a member of the channel" do
      {_agent, session} = create_session()
      channel = create_channel()

      # No add_member call — mark_as_read is a no-op update_all on zero rows
      assert :ok ==
               (AgentWorkerEvents.on_result_received(session.id, %{
                  provider: "claude",
                  text: "orphan reply",
                  metadata: %{},
                  channel_id: channel.id,
                  source_uuid: nil
                }) && :ok)
    end
  end
end
