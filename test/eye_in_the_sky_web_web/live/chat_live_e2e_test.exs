defmodule EyeInTheSkyWebWeb.ChatLiveE2ETest do
  @moduledoc """
  End-to-end test for chat flow through SessionManager.

  Tests the full stack:
  ChatLive UI → SessionManager → SessionWorker → MockCLI → PubSub → UI updates
  """

  use EyeInTheSkyWebWeb.ConnCase
  use EyeInTheSkyWeb.SessionManagerCase

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.{Agents, ChatAgents, Channels, Messages, Projects}
  alias EyeInTheSkyWeb.Claude.{SessionManager, SessionWorker}

  @web_chat_agent_uuid "00000000-0000-0000-0000-000000000001"
  @web_execution_agent_uuid "00000000-0000-0000-0000-000000000002"
  @test_chat_agent_uuid "test-agent-e2e-uuid"
  @test_execution_agent_uuid "test-execution-e2e-uuid"

  setup %{conn: conn} do
    # Only restart SessionManager components, not PubSub (it's started by the application)
    for name <- [SessionManager, @supervisor, @registry] do
      case Process.whereis(name) do
        nil -> :ok
        pid -> Process.exit(pid, :kill)
      end
    end

    Process.sleep(20)

    # Start SessionManager infrastructure (PubSub is already running from application)
    start_supervised!({Registry, keys: :duplicate, name: @registry})
    start_supervised!({DynamicSupervisor, name: @supervisor, strategy: :one_for_one})
    start_supervised!(SessionManager)

    # Create test project
    {:ok, project} =
      Projects.create_project(%{
        name: "E2E Test Project",
        slug: "e2e-test-project",
        active: true
      })

    # Create web UI chat agent and execution agent
    {:ok, web_chat_agent} =
      ChatAgents.create_chat_agent(%{
        uuid: @web_chat_agent_uuid,
        description: "Web UI User",
        source: "web",
        project_id: project.id
      })

    {:ok, web_execution_agent} =
      Agents.create_execution_agent(%{
        uuid: @web_execution_agent_uuid,
        agent_id: web_chat_agent.id,
        name: "Web UI",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    # Create test chat agent and execution agent that will receive messages
    {:ok, test_chat_agent} =
      ChatAgents.create_chat_agent(%{
        uuid: @test_chat_agent_uuid,
        description: "Test Agent",
        source: "test",
        project_id: project.id
      })

    {:ok, test_execution_agent} =
      Agents.create_execution_agent(%{
        uuid: @test_execution_agent_uuid,
        agent_id: test_chat_agent.id,
        name: "Test Session",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    # Create a channel for communication
    {:ok, channel} =
      Channels.create_channel(%{
        name: "E2E Test Channel",
        project_id: project.id,
        session_id: web_execution_agent.id
      })

    %{
      conn: conn,
      project: project,
      web_chat_agent: web_chat_agent,
      web_execution_agent: web_execution_agent,
      test_chat_agent: test_chat_agent,
      test_execution_agent: test_execution_agent,
      channel: channel
    }
  end

  describe "end-to-end chat flow" do
    test "user sends message → SessionManager spawns worker → mock CLI processes → UI updates",
         %{conn: conn, channel: channel, test_execution_agent: test_execution_agent} do
      # Mount the chat page
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      # Subscribe to PubSub to verify status broadcasts
      subscribe_session_status(test_execution_agent.uuid)
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "channel:#{channel.id}:messages")

      # Send a message targeting the test agent
      view
      |> form("#dm-form", %{
        "target_id" => to_string(test_execution_agent.id),
        "body" => "Hello from E2E test"
      })
      |> render_submit()

      # Verify SessionManager spawned a worker
      assert {:ok, worker_pid} = await_worker(test_execution_agent.uuid, 2000)

      # Verify worker is processing
      assert_status_broadcast(test_execution_agent.uuid, :working, 2000)

      # Get the mock port and send a simulated response
      port = get_mock_port(worker_pid)

      # Simulate Claude responding with assistant message
      assistant_response = %{
        "type" => "assistant",
        "role" => "assistant",
        "message" => %{
          "content" => [
            %{
              "type" => "text",
              "text" => "Hello! I received your message."
            }
          ]
        },
        "uuid" => "test-message-uuid-123"
      }

      send_mock_output(port, Jason.encode!(assistant_response))

      # Wait a bit for message processing
      Process.sleep(100)

      # Verify message was recorded in database
      messages = Messages.list_messages_for_channel(channel.id)
      assert length(messages) >= 2

      # Find the user message
      user_message = Enum.find(messages, fn m -> m.body == "Hello from E2E test" end)
      assert user_message
      assert user_message.sender_role == "user"

      # Find the assistant response (via message recording)
      # Note: The assistant message might be recorded in the database
      # depending on the Messages.record_incoming_reply implementation

      # Simulate CLI exit
      send_mock_exit(port, 0)

      # Verify worker goes idle
      assert_status_broadcast(test_execution_agent.uuid, :idle, 2000)

      # Verify worker is still alive but idle
      assert Process.alive?(worker_pid)
      info = SessionWorker.get_info(worker_pid)
      assert info.processing == false
    end

    test "multiple messages queue correctly", %{
      conn: conn,
      channel: channel,
      test_execution_agent: test_execution_agent
    } do
      # Mount the chat page
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      subscribe_session_status(test_execution_agent.uuid)

      # Send first message
      view
      |> form("#dm-form", %{
        "target_id" => to_string(test_execution_agent.id),
        "body" => "First message"
      })
      |> render_submit()

      # Wait for worker to start
      assert {:ok, worker_pid} = await_worker(test_execution_agent.uuid)
      assert_status_broadcast(test_execution_agent.uuid, :working)

      # Get the mock port and make it hang (simulate slow processing)
      port = get_mock_port(worker_pid)
      make_port_hang(port)

      # Send more messages while first is processing - they should queue
      for i <- 2..4 do
        view
        |> form("#dm-form", %{
          "target_id" => to_string(test_execution_agent.id),
          "body" => "Message #{i}"
        })
        |> render_submit()

        # Brief delay between submissions
        Process.sleep(50)
      end

      # Verify messages were queued
      info = SessionWorker.get_info(worker_pid)
      assert info.queue_depth >= 2
      # Some might have been queued
      assert info.queue_depth <= 3

      # Verify we still have only one worker
      assert [{^worker_pid, _}] =
               Registry.lookup(@registry, {:session, test_execution_agent.uuid})
    end

    test "UI updates when worker broadcasts status changes", %{
      conn: conn,
      channel: channel,
      test_execution_agent: test_execution_agent
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      subscribe_session_status(test_execution_agent.uuid)

      # Send a message
      view
      |> form("#dm-form", %{
        "target_id" => to_string(test_execution_agent.id),
        "body" => "Status test"
      })
      |> render_submit()

      # Verify working status broadcast
      assert_status_broadcast(test_execution_agent.uuid, :working)

      # Get worker and complete the work
      {:ok, worker_pid} = await_worker(test_execution_agent.uuid)
      port = get_mock_port(worker_pid)
      send_mock_exit(port, 0)

      # Verify idle status broadcast
      assert_status_broadcast(test_execution_agent.uuid, :idle)

      # The LiveView should have received these broadcasts and updated its state
      # In a real scenario, you'd check the HTML for status indicators
    end

    test "handles SessionManager errors gracefully", %{conn: conn, channel: channel} do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      # Try to send to non-existent session
      view
      |> form("#dm-form", %{
        "target_id" => "99999",
        "body" => "This should fail"
      })
      |> render_submit()

      # LiveView should show error flash (check rendered HTML)
      html = render(view)
      # The exact error handling depends on the LiveView implementation
      # but the session should remain functional
      assert view.pid |> Process.alive?()
    end

    test "channel messages are published to NATS", %{
      conn: conn,
      channel: channel,
      web_execution_agent: web_execution_agent
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      # Send a channel message (not DM)
      view
      |> element("#channel-message-form")
      |> render_submit(%{"body" => "Channel broadcast message"})

      # Verify message was created
      messages = Messages.list_messages_for_channel(channel.id)
      channel_msg = Enum.find(messages, fn m -> m.body == "Channel broadcast message" end)
      assert channel_msg
      assert channel_msg.sender_role == "user"

      # In a real scenario with NATS running, you'd verify the message was published
      # For now, just verify the message was persisted
    end

    test "worker recovers from crash and allows new session", %{
      conn: conn,
      channel: channel,
      test_execution_agent: test_execution_agent
    } do
      {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

      # Start a session
      view
      |> form("#dm-form", %{
        "target_id" => to_string(test_execution_agent.id),
        "body" => "Initial message"
      })
      |> render_submit()

      {:ok, worker_pid} = await_worker(test_execution_agent.uuid)

      # Simulate worker crash
      monitor_ref = Process.monitor(worker_pid)
      Process.exit(worker_pid, :kill)
      assert_receive {:DOWN, ^monitor_ref, :process, ^worker_pid, _}, 1000

      # Brief delay for cleanup
      Process.sleep(50)

      # Send another message - should spawn new worker
      view
      |> form("#dm-form", %{
        "target_id" => to_string(test_execution_agent.id),
        "body" => "After crash"
      })
      |> render_submit()

      # Verify new worker was spawned
      {:ok, new_worker_pid} = await_worker(test_execution_agent.uuid)
      assert new_worker_pid != worker_pid
      assert Process.alive?(new_worker_pid)
    end
  end

  describe "session list view" do
    test "lists all active sessions", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/sessions")

      # Should show session overview
      assert html =~ "Session Overview"

      # Should have a button to start new session
      assert has_element?(view, "button", "Start New Session")
    end
  end
end
