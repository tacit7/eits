defmodule EyeInTheSkyWeb.RealE2ETest do
  @moduledoc """
  Real end-to-end integration test with actual Claude CLI processes.

  NO MOCKS. This test:
  1. Spawns a real Claude CLI session with -p and --session flags
  2. Uses the real SessionManager
  3. Simulates @mention in web chat
  4. Verifies message delivery through the full stack

  REQUIRES: claude binary in PATH
  """

  use EyeInTheSkyWebWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.{Agents, Channels, Messages, Projects, Sessions}
  alias EyeInTheSkyWeb.Claude.SessionManager

  @moduletag :integration
  @moduletag timeout: 60_000  # Real CLI can be slow

  @test_project_path "/tmp/eits-e2e-test-project"
  @test_session_uuid "e2e-test-session-#{System.system_time(:second)}"

  setup do
    # Override MockCLI to use real CLI for this test
    Application.put_env(:eye_in_the_sky_web, :cli_module, EyeInTheSkyWeb.Claude.CLI)

    on_exit(fn ->
      Application.put_env(:eye_in_the_sky_web, :cli_module, EyeInTheSkyWeb.Claude.MockCLI)
    end)

    # Ensure test project directory exists
    File.mkdir_p!(@test_project_path)

    # Create test project in DB (timestamps handled by DB defaults)
    {:ok, project} = Projects.create_project(%{
      name: "E2E Integration Test",
      slug: "e2e-integration-test",
      path: @test_project_path,
      active: true
    })

    # Create test agent
    {:ok, agent} = Agents.create_agent(%{
      uuid: "e2e-agent-#{System.system_time(:second)}",
      description: "E2E Test Agent",
      source: "test",
      project_id: project.id
    })

    # Create test session (this will be used by CLI with --session flag)
    {:ok, session} = Sessions.create_session(%{
      uuid: @test_session_uuid,
      agent_id: agent.id,
      name: "E2E Test Session",
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    # Create channel for communication
    {:ok, channel} = Channels.create_channel(%{
      uuid: "e2e-channel-#{System.system_time(:second)}",
      name: "E2E Test Channel",
      project_id: project.id,
      session_id: session.id
    })

    # Create web UI agent/session for sending messages (with unique UUIDs)
    {:ok, web_agent} = Agents.create_agent(%{
      uuid: "e2e-web-agent-#{System.system_time(:second)}",
      description: "Web UI User",
      source: "web",
      project_id: project.id
    })

    {:ok, web_session} = Sessions.create_session(%{
      uuid: "e2e-web-session-#{System.system_time(:second)}",
      agent_id: web_agent.id,
      name: "Web UI",
      started_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    %{
      project: project,
      agent: agent,
      session: session,
      channel: channel,
      web_session: web_session
    }
  end

  # Remove :skip tag to run with real Claude (requires claude binary)
  @tag :skip
  test "full E2E: spawn real Claude CLI → @mention → message delivered",
       %{conn: conn, session: session, channel: channel} do
    # STEP 1: Start a real Claude CLI session using SessionManager
    # This will spawn an actual claude process with -p and --session flags
    prompt = "You are a test agent. Respond with 'TEST_OK' when you receive messages."

    {:ok, session_ref} = SessionManager.resume_session(
      session.uuid,
      prompt,
      model: "haiku",  # Use haiku for speed
      project_path: @test_project_path,
      session_id: session.uuid
    )

    # Verify worker was spawned
    assert session_ref != :queued
    assert is_reference(session_ref)

    # Wait for CLI to initialize (real CLI needs time)
    Process.sleep(2000)

    # Verify worker is in registry
    registry = EyeInTheSkyWeb.Claude.Registry
    workers = Registry.lookup(registry, {:session, session.uuid})
    assert length(workers) == 1
    [{worker_pid, _}] = workers
    assert Process.alive?(worker_pid)

    # STEP 2: Mount chat LiveView
    {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

    # Subscribe to channel messages
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "channel:#{channel.id}:messages")
    Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session.uuid}:status")

    # STEP 3: Simulate @mention (send DM to the agent)
    # Trigger the send_direct_message event (UI is Svelte, not Phoenix forms)
    render_hook(view, "send_direct_message", %{
      "session_id" => to_string(session.id),
      "channel_id" => to_string(channel.id),
      "body" => "@agent please respond"
    })

    # STEP 4: Wait for message to be sent to Claude
    # The SessionManager should have queued or processed the message
    # Real Claude CLI will take time to respond

    # Verify the outbound message was created
    Process.sleep(500)  # Brief delay for DB write
    messages = Messages.list_messages_for_channel(channel.id)
    outbound = Enum.find(messages, fn m -> m.body =~ "@agent please respond" end)
    assert outbound, "Outbound message not found in database"
    assert outbound.sender_role == "user"
    assert outbound.recipient_role == "agent"

    # STEP 5: Wait for Claude response (real CLI can take 5-10 seconds)
    # Listen for PubSub broadcast of new message
    response_received = receive do
      {:new_message, msg} when msg.sender_role == "agent" ->
        IO.puts("Received agent response: #{inspect(msg.body)}")
        true
      {:session_status, ^session, :working} ->
        IO.puts("Session is working...")
        # Keep waiting
        receive do
          {:new_message, msg} when msg.sender_role == "agent" -> true
        after
          30_000 -> false
        end
      other ->
        IO.puts("Unexpected message: #{inspect(other)}")
        false
    after
      30_000 ->
        IO.puts("Timeout waiting for agent response")
        false
    end

    assert response_received, "Did not receive agent response within timeout"

    # STEP 6: Verify response was persisted
    final_messages = Messages.list_messages_for_channel(channel.id)
    agent_responses = Enum.filter(final_messages, fn m ->
      m.sender_role == "agent" && m.recipient_role == "user"
    end)

    assert length(agent_responses) >= 1, "No agent responses found in database"

    # STEP 7: Cleanup - cancel the session
    :ok = SessionManager.cancel_session(session_ref)

    # Wait for worker to stop
    Process.sleep(500)
    ref = Process.monitor(worker_pid)
    receive do
      {:DOWN, ^ref, :process, ^worker_pid, _reason} -> :ok
    after
      5_000 -> :ok
    end
  end

  test "database schema and test setup works", %{session: session, channel: channel, conn: conn} do
    # Verify the test database has correct schema
    {:ok, view, _html} = live(conn, ~p"/chat?channel_id=#{channel.id}")

    # Trigger send_direct_message event
    render_hook(view, "send_direct_message", %{
      "session_id" => to_string(session.id),
      "channel_id" => to_string(channel.id),
      "body" => "Test message"
    })

    # Verify message was created in database
    Process.sleep(100)
    messages = Messages.list_messages_for_channel(channel.id)
    test_msg = Enum.find(messages, fn m -> m.body == "Test message" end)

    assert test_msg, "Test message should be in database"
    assert test_msg.sender_role == "user"
  end

  @tag :skip
  test "real CLI process lifecycle", %{session: session} do
    # Test just the CLI spawning part without full UI
    prompt = "Test prompt"

    {:ok, session_ref} = SessionManager.resume_session(
      session.uuid,
      prompt,
      model: "haiku",
      project_path: @test_project_path
    )

    assert is_reference(session_ref)

    # Wait for initialization
    Process.sleep(1000)

    # Verify worker exists
    registry = EyeInTheSkyWeb.Claude.Registry
    assert [{worker_pid, _}] = Registry.lookup(registry, {:session, session.uuid})
    assert Process.alive?(worker_pid)

    # Get worker info
    worker_info = EyeInTheSkyWeb.Claude.SessionWorker.get_info(worker_pid)
    assert worker_info.session_id == session.uuid
    assert worker_info.processing == true

    # Cancel
    :ok = SessionManager.cancel_session(session_ref)

    # Worker should stop
    Process.sleep(500)
    assert !Process.alive?(worker_pid)
  end

  @tag :skip
  test "multiple messages queue correctly with real CLI", %{session: session} do
    # Start session
    {:ok, ref1} = SessionManager.resume_session(
      session.uuid,
      "First message",
      model: "haiku",
      project_path: @test_project_path
    )

    Process.sleep(1000)

    # Queue more messages while first is processing
    {:ok, :queued} = SessionManager.resume_session(session.uuid, "Second message", [])
    {:ok, :queued} = SessionManager.resume_session(session.uuid, "Third message", [])

    # Verify queue depth
    registry = EyeInTheSkyWeb.Claude.Registry
    [{worker_pid, _}] = Registry.lookup(registry, {:session, session.uuid})

    worker_info = EyeInTheSkyWeb.Claude.SessionWorker.get_info(worker_pid)
    assert worker_info.queue_depth == 2

    # Cleanup
    SessionManager.cancel_session(ref1)
  end
end
