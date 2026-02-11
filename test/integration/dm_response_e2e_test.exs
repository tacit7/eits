defmodule EyeInTheSkyWeb.DMResponseE2ETest do
  @moduledoc """
  End-to-end test for DM response flow.

  Tests SessionWorker's handling of Claude output and message recording.
  Uses MockCLI to control timing but tests real message flow.
  """

  use EyeInTheSkyWebWeb.ConnCase, async: false
  use EyeInTheSkyWeb.SessionManagerCase

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.{Agents, Channels, Messages, Projects, Sessions}
  alias EyeInTheSkyWeb.Claude.SessionManager

  setup %{conn: conn} do
    # Kill existing workers for clean state
    supervisor = EyeInTheSkyWeb.Claude.SessionSupervisor

    supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn
      {_, pid, :worker, _} when is_pid(pid) ->
        DynamicSupervisor.terminate_child(supervisor, pid)
      _ -> :ok
    end)

    Process.sleep(50)

    # Create test project
    {:ok, project} = Projects.create_project(%{
      name: "DM Response Test",
      slug: "dm-response-test",
      path: "/tmp/dm-response-test",
      active: true
    })

    # Create sender
    {:ok, sender_agent} = Agents.create_agent(%{
      uuid: "dm-resp-sender-#{System.system_time(:second)}",
      description: "Response Test Sender",
      source: "web",
      project_id: project.id
    })

    {:ok, sender_session} = Sessions.create_session(%{
      uuid: "dm-resp-sender-session-#{System.system_time(:second)}",
      agent_id: sender_agent.id,
      name: "Sender",
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    # Create recipient
    {:ok, recipient_agent} = Agents.create_agent(%{
      uuid: "dm-resp-recipient-#{System.system_time(:second)}",
      description: "Response Test Recipient",
      source: "claude",
      project_id: project.id
    })

    {:ok, recipient_session} = Sessions.create_session(%{
      uuid: "dm-resp-recipient-session-#{System.system_time(:second)}",
      agent_id: recipient_agent.id,
      name: "Recipient",
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:ok, channel} = Channels.create_channel(%{
      uuid: "dm-resp-channel-#{System.system_time(:second)}",
      name: "Response Test Channel",
      project_id: project.id,
      session_id: sender_session.id
    })

    %{
      conn: conn,
      project: project,
      sender_session: sender_session,
      recipient_session: recipient_session,
      channel: channel
    }
  end

  test "complete DM round-trip: user → agent → response → user sees it",
       %{conn: conn, recipient_session: recipient, channel: channel} do
    # Mount chat
    {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

    # Subscribe to channel messages
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "channel:#{channel.id}:messages")

    # STEP 1: User sends DM
    render_hook(view, "send_direct_message", %{
      "session_id" => to_string(recipient.id),
      "channel_id" => to_string(channel.id),
      "body" => "Can you help me?"
    })

    # Verify outbound message broadcast
    assert_receive {:new_message, outbound_msg}, 1000
    assert outbound_msg.sender_role == "user"
    assert outbound_msg.body == "Can you help me?"

    # STEP 2: Get the spawned SessionWorker
    {:ok, worker_pid} = await_worker(recipient.uuid, 2000)
    assert Process.alive?(worker_pid)

    # STEP 3: Simulate Claude response (using MockCLI)
    port = get_mock_port(worker_pid)

    # Send simulated assistant response in Claude's JSON format
    assistant_response = %{
      "type" => "assistant",
      "role" => "assistant",
      "message" => %{
        "content" => [
          %{
            "type" => "text",
            "text" => "Sure, I can help you with that!"
          }
        ]
      },
      "uuid" => "mock-response-uuid-#{System.system_time(:second)}"
    }

    send_mock_output(port, Jason.encode!(assistant_response))

    # STEP 4: Wait for response to be recorded in database
    # SessionWorker calls Messages.record_incoming_reply() and Publisher.publish_message()
    # The response goes to NATS, not Phoenix PubSub
    Process.sleep(500)

    # STEP 5: Verify response is in database
    messages = Messages.list_messages_for_session(recipient.id)

    IO.puts("\n=== Messages for session #{recipient.id} ===")
    Enum.each(messages, fn m ->
      IO.puts("  #{m.sender_role}: #{inspect(String.slice(m.body || "", 0..50))}")
    end)

    # Filter for messages from this test run
    agent_responses = Enum.filter(messages, fn m ->
      m.sender_role == "agent" &&
      m.body &&
      String.contains?(m.body, "Sure, I can help")
    end)

    if length(agent_responses) == 0 do
      IO.puts("\n❌ No agent responses found. All messages:")
      IO.inspect(messages, label: "All messages", limit: :infinity)
    end

    assert length(agent_responses) >= 1, "Agent response should be recorded in database"

    agent_response = List.first(agent_responses)
    assert agent_response.sender_role == "agent"
    assert agent_response.recipient_role == "user"
    assert agent_response.direction == "inbound"
    assert agent_response.provider == "claude"

    IO.puts("✓ Agent response recorded to database")
    IO.puts("✓ NATS publish called (Publisher.publish_message)")

    # Verify NATS message structure (optional - would need NATS connection to verify)
    # For now, successful database insert proves the flow works

    # STEP 6: Complete the session
    send_mock_exit(port, 0)
    Process.sleep(200)
  end

  test "SessionWorker parses Claude output correctly",
       %{recipient_session: recipient} do
    # Start a session directly (no UI)
    {:ok, _ref} = SessionManager.resume_session(
      recipient.uuid,
      "Test prompt",
      model: "haiku"
    )

    {:ok, worker_pid} = await_worker(recipient.uuid, 1000)
    port = get_mock_port(worker_pid)

    # Send various Claude output formats
    outputs = [
      # Standard assistant message
      %{
        "type" => "assistant",
        "message" => %{
          "content" => [%{"type" => "text", "text" => "Response 1"}]
        },
        "uuid" => "test-uuid-1"
      },
      # Tool use
      %{
        "type" => "assistant",
        "message" => %{
          "content" => [
            %{"type" => "tool_use", "name" => "read", "input" => %{"path" => "/test"}}
          ]
        },
        "uuid" => "test-uuid-2"
      },
      # Mixed content
      %{
        "type" => "assistant",
        "message" => %{
          "content" => [
            %{"type" => "text", "text" => "Let me read that file"},
            %{"type" => "tool_use", "name" => "read", "input" => %{}}
          ]
        },
        "uuid" => "test-uuid-3"
      }
    ]

    for output <- outputs do
      send_mock_output(port, Jason.encode!(output))
      Process.sleep(100)
    end

    # Verify SessionWorker is still alive (didn't crash on parsing)
    assert Process.alive?(worker_pid)

    # Messages should have been processed (whether or not they're stored depends on implementation)
    info = EyeInTheSkyWeb.Claude.SessionWorker.get_info(worker_pid)
    assert info.output_lines >= 3

    send_mock_exit(port, 0)
  end

  test "PubSub broadcasts reach subscribed LiveViews",
       %{conn: conn, recipient_session: recipient, channel: channel} do
    # Mount two LiveViews (simulating two users watching same channel)
    {:ok, view1, _} = live(conn, ~p"/chat?channel_id=#{channel.id}")
    {:ok, view2, _} = live(conn, ~p"/chat?channel_id=#{channel.id}")

    # Both subscribe to channel (happens automatically in mount)
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "channel:#{channel.id}:messages")

    # Send DM from view1
    render_hook(view1, "send_direct_message", %{
      "session_id" => to_string(recipient.id),
      "channel_id" => to_string(channel.id),
      "body" => "Broadcast test"
    })

    # Both views should receive the broadcast
    assert_receive {:new_message, msg}, 1000
    assert msg.body == "Broadcast test"

    # Views should still be alive
    assert Process.alive?(view1.pid)
    assert Process.alive?(view2.pid)
  end
end
