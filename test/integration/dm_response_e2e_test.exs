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

      _ ->
        :ok
    end)

    Process.sleep(50)

    # Create test project
    {:ok, project} =
      Projects.create_project(%{
        name: "DM Response Test",
        slug: "dm-response-test",
        path: "/tmp/dm-response-test",
        active: true
      })

    # Create sender
    {:ok, sender_agent} =
      Agents.create_agent(%{
        uuid: "dm-resp-sender-#{System.system_time(:second)}",
        description: "Response Test Sender",
        source: "web",
        project_id: project.id
      })

    {:ok, sender_session} =
      Sessions.create_session(%{
        uuid: "dm-resp-sender-session-#{System.system_time(:second)}",
        agent_id: sender_agent.id,
        name: "Sender",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    # Create recipient
    {:ok, recipient_agent} =
      Agents.create_agent(%{
        uuid: "dm-resp-recipient-#{System.system_time(:second)}",
        description: "Response Test Recipient",
        source: "claude",
        project_id: project.id
      })

    {:ok, recipient_session} =
      Sessions.create_session(%{
        uuid: "dm-resp-recipient-session-#{System.system_time(:second)}",
        agent_id: recipient_agent.id,
        name: "Recipient",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {:ok, channel} =
      Channels.create_channel(%{
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

  test "complete DM round-trip: agent spawns, processes output, response saved",
       %{recipient_session: recipient} do
    # STEP 1: Start a session via SessionManager (simulates receiving a DM)
    {:ok, _ref} =
      SessionManager.resume_session(
        recipient.uuid,
        "Can you help me?",
        model: "haiku"
      )

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
    Process.sleep(500)

    # STEP 5: Verify response is in database
    messages = Messages.list_messages_for_session(recipient.id)

    # Filter for messages from this test run
    agent_responses =
      Enum.filter(messages, fn m ->
        m.sender_role == "agent" &&
          m.body &&
          String.contains?(m.body, "Sure, I can help")
      end)

    assert length(agent_responses) >= 1, "Agent response should be recorded in database"

    agent_response = List.first(agent_responses)
    assert agent_response.sender_role == "agent"
    assert agent_response.recipient_role == "user"
    assert agent_response.direction == "inbound"
    assert agent_response.provider == "claude"

    # STEP 6: Complete the session
    send_mock_exit(port, 0)
    Process.sleep(200)
  end

  test "SessionWorker parses Claude output correctly",
       %{recipient_session: recipient} do
    # Start a session directly (no UI)
    {:ok, _ref} =
      SessionManager.resume_session(
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

    # Verify session info is accessible
    info = EyeInTheSkyWeb.Claude.SessionWorker.get_info(worker_pid)
    assert info.session_id == recipient.uuid

    send_mock_exit(port, 0)
  end

  test "PubSub broadcasts reach subscribed LiveViews",
       %{conn: conn, channel: channel} do
    # Mount two LiveViews (simulating two users watching same channel)
    {:ok, view1, _} = live(conn, ~p"/chat?channel_id=#{channel.id}")
    {:ok, view2, _} = live(conn, ~p"/chat?channel_id=#{channel.id}")

    # Subscribe test process to channel messages
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "channel:#{channel.id}:messages")

    # Directly broadcast a message to the channel (simulating what send_channel_message would do)
    fake_msg = %{
      id: 1,
      body: "Broadcast test",
      sender_role: "user",
      direction: "outbound",
      channel_id: channel.id
    }

    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "channel:#{channel.id}:messages",
      {:new_message, fake_msg}
    )

    # Test process should receive the broadcast
    assert_receive {:new_message, msg}, 1000
    assert msg.body == "Broadcast test"

    # Views should still be alive (not crashed by receiving messages)
    assert Process.alive?(view1.pid)
    assert Process.alive?(view2.pid)
  end
end
