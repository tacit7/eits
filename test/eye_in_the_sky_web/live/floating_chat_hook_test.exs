defmodule EyeInTheSkyWeb.FloatingChatHookTest do
  @moduledoc """
  Tests for FloatingChatLive on_mount hook.

  Tests the FAB (Floating Action Button) functionality:
  - bookmark management and status fetching
  - message routing to active sessions
  - session subscription lifecycle
  """

  use EyeInTheSkyWeb.ConnCase

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Agents, Messages, Sessions}

  setup %{conn: conn} do
    # Create test agents and sessions
    {:ok, agent1} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Test Agent 1",
        source: "api"
      })

    {:ok, session1} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent1.id,
        name: "Test Session 1",
        status: "idle",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {:ok, agent2} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Test Agent 2",
        source: "api"
      })

    {:ok, session2} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent2.id,
        name: "Test Session 2",
        status: "working",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    %{
      conn: conn,
      session1: session1,
      session2: session2
    }
  end

  describe "FloatingChatLive on_mount hook" do
    test "initializes FAB assigns on mount", %{conn: conn} do
      # The hook attaches to chat_live which we can test
      {:ok, view, _html} = live(conn, "/chat")

      assert view.assigns.fab_mounted == true
      assert view.assigns.fab_timer == nil
      assert view.assigns.fab_active_session_id == nil
      assert view.assigns.config_guide_active_session_id == nil
      assert view.assigns.fab_bookmarks == []
      assert view.assigns.fab_statuses == %{}
    end

    test "fab_set_bookmarks fetches statuses", %{
      conn: conn,
      session1: session1,
      session2: session2
    } do
      {:ok, view, _html} = live(conn, "/chat")

      bookmarks = [to_string(session1.id), to_string(session2.id)]

      render_hook(view, "fab_set_bookmarks", %{"bookmarks" => bookmarks})

      # Verify bookmarks were set
      assert view.assigns.fab_bookmarks == bookmarks

      # Verify statuses fetched
      assert Map.has_key?(view.assigns.fab_statuses, to_string(session1.id))
      assert Map.has_key?(view.assigns.fab_statuses, to_string(session2.id))

      # Verify correct statuses
      assert view.assigns.fab_statuses[to_string(session1.id)] == "idle"
      assert view.assigns.fab_statuses[to_string(session2.id)] == "working"
    end

    test "fab_request_statuses refreshes statuses", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      bookmarks = [to_string(session1.id)]
      render_hook(view, "fab_set_bookmarks", %{"bookmarks" => bookmarks})

      # Schedule a refresh
      render_hook(view, "fab_request_statuses", %{})

      # Verify statuses were updated
      assert Map.has_key?(view.assigns.fab_statuses, to_string(session1.id))
    end

    test "fab_open_chat opens session and subscribes", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "fab_open_chat", %{"session_id" => to_string(session1.id)})

      # Verify session was switched
      assert view.assigns.fab_active_session_id == session1.id

      # Verify subscribed to session messages
      topic = "session:#{session1.id}:messages"
      subscribers =
        Registry.lookup(EyeInTheSky.PubSub, topic)
        |> Enum.map(fn {pid, _} -> pid end)

      assert view.pid in subscribers
    end

    test "fab_close_chat closes session and unsubscribes", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      # Open chat first
      render_hook(view, "fab_open_chat", %{"session_id" => to_string(session1.id)})
      assert view.assigns.fab_active_session_id == session1.id

      # Close chat
      render_hook(view, "fab_close_chat", %{})

      assert view.assigns.fab_active_session_id == nil

      # Verify unsubscribed
      topic = "session:#{session1.id}:messages"
      subscribers =
        Registry.lookup(EyeInTheSky.PubSub, topic)
        |> Enum.map(fn {pid, _} -> pid end)

      assert view.pid not in subscribers
    end

    test "fab_send_message sends to session", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "fab_send_message", %{
        "session_id" => to_string(session1.id),
        "body" => "FAB message"
      })

      # Verify message was saved
      messages = Messages.list_recent_messages(session1.id, 10)
      assert Enum.any?(messages, fn m -> m.body == "FAB message" end)
    end

    test "config_guide_open_chat opens config guide session", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "config_guide_open_chat", %{"session_id" => to_string(session1.id)})

      # Verify config guide session set
      assert view.assigns.config_guide_active_session_id == session1.id

      # Verify subscribed
      topic = "session:#{session1.id}:messages"
      subscribers =
        Registry.lookup(EyeInTheSky.PubSub, topic)
        |> Enum.map(fn {pid, _} -> pid end)

      assert view.pid in subscribers
    end

    test "config_guide_send_message sends to config guide session", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "config_guide_send_message", %{
        "session_id" => to_string(session1.id),
        "body" => "Config message"
      })

      # Verify message was saved
      messages = Messages.list_recent_messages(session1.id, 10)
      assert Enum.any?(messages, fn m -> m.body == "Config message" end)
    end

    test "config_guide_close_chat closes config guide session", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "config_guide_open_chat", %{"session_id" => to_string(session1.id)})
      assert view.assigns.config_guide_active_session_id == session1.id

      render_hook(view, "config_guide_close_chat", %{})

      assert view.assigns.config_guide_active_session_id == nil

      # Verify unsubscribed
      topic = "session:#{session1.id}:messages"
      subscribers =
        Registry.lookup(EyeInTheSky.PubSub, topic)
        |> Enum.map(fn {pid, _} -> pid end)

      assert view.pid not in subscribers
    end

    test "new_message routes to fab_chat if session is active", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      # Open FAB chat
      render_hook(view, "fab_open_chat", %{"session_id" => to_string(session1.id)})
      assert view.assigns.fab_active_session_id == session1.id

      # Create and broadcast message from agent
      {:ok, msg} =
        Messages.send_message(%{
          session_id: session1.id,
          sender_role: "agent",
          recipient_role: "user",
          provider: "claude",
          body: "Agent response"
        })

      EyeInTheSky.Events.notify_new_message(msg)
      :ok = render(view)

      # Verify message routed (session still active)
      assert view.assigns.fab_active_session_id == session1.id
    end

    test "new_message ignored for user messages", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      # Create user message (should not route)
      {:ok, _msg} =
        Messages.send_message(%{
          session_id: session1.id,
          sender_role: "user",
          recipient_role: "agent",
          provider: "claude",
          body: "User input"
        })

      initial_id = view.assigns.fab_active_session_id

      EyeInTheSky.Events.notify_new_message(_msg)
      :ok = render(view)

      # Should be unchanged
      assert view.assigns.fab_active_session_id == initial_id
    end

    test "handles empty bookmarks list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "fab_set_bookmarks", %{"bookmarks" => []})

      assert view.assigns.fab_bookmarks == []
      assert view.assigns.fab_statuses == %{}
    end

    test "handles mixed UUID and integer bookmarks", %{
      conn: conn,
      session1: session1,
      session2: session2
    } do
      {:ok, view, _html} = live(conn, "/chat")

      # Mix of ID and UUID
      bookmarks = [to_string(session1.id), session2.uuid]

      render_hook(view, "fab_set_bookmarks", %{"bookmarks" => bookmarks})

      # Both should be found
      statuses = view.assigns.fab_statuses
      assert Map.size(statuses) >= 2
    end
  end
end
