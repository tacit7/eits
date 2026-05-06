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

  # Access socket assigns from a LiveViewTest view via the channel process state.
  # Phoenix.LiveViewTest.View.pid is the LiveView Channel GenServer;
  # its state map has a :socket key.
  defp view_assigns(view) do
    %{socket: socket} = :sys.get_state(view.pid)
    socket.assigns
  end

  # Build the bookmark object structure as stored by the JS BookmarkAgent hook
  # (localStorage: [{agent_id, session_id, name, status}, ...])
  defp bookmark(session) do
    %{
      "agent_id" => to_string(session.agent_id),
      "session_id" => to_string(session.id),
      "name" => session.name,
      "status" => session.status
    }
  end

  setup %{conn: conn} do
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
      {:ok, view, _html} = live(conn, "/chat")

      assigns = view_assigns(view)
      assert assigns.fab_mounted == true
      assert assigns.fab_timer == nil
      assert assigns.fab_active_session_id == nil
      assert assigns.config_guide_active_session_id == nil
      assert assigns.fab_bookmarks == []
      assert assigns.fab_statuses == %{}
    end

    test "fab_set_bookmarks fetches statuses", %{
      conn: conn,
      session1: session1,
      session2: session2
    } do
      {:ok, view, _html} = live(conn, "/chat")

      bookmarks = [bookmark(session1), bookmark(session2)]
      render_hook(view, "fab_set_bookmarks", %{"bookmarks" => bookmarks})

      assigns = view_assigns(view)

      # Verify bookmarks were set
      assert assigns.fab_bookmarks == bookmarks

      # Verify statuses fetched by integer session ID key
      assert Map.has_key?(assigns.fab_statuses, to_string(session1.id))
      assert Map.has_key?(assigns.fab_statuses, to_string(session2.id))

      assert assigns.fab_statuses[to_string(session1.id)] == "idle"
      assert assigns.fab_statuses[to_string(session2.id)] == "working"
    end

    test "fab_request_statuses refreshes statuses", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "fab_set_bookmarks", %{"bookmarks" => [bookmark(session1)]})
      render_hook(view, "fab_request_statuses", %{})

      assert Map.has_key?(view_assigns(view).fab_statuses, to_string(session1.id))
    end

    test "fab_open_chat opens session and subscribes", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "fab_open_chat", %{"session_id" => to_string(session1.id)})

      assert view_assigns(view).fab_active_session_id == session1.id

      # subscribe_session subscribes to "session:#{id}" (not the :messages sub-topic)
      topic = "session:#{session1.id}"

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

      render_hook(view, "fab_open_chat", %{"session_id" => to_string(session1.id)})
      assert view_assigns(view).fab_active_session_id == session1.id

      render_hook(view, "fab_close_chat", %{})

      assert view_assigns(view).fab_active_session_id == nil

      topic = "session:#{session1.id}"

      subscribers =
        Registry.lookup(EyeInTheSky.PubSub, topic)
        |> Enum.map(fn {pid, _} -> pid end)

      assert view.pid not in subscribers
    end

    test "fab_send_message saves message to DB", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "fab_send_message", %{
        "session_id" => to_string(session1.id),
        "body" => "FAB message"
      })

      messages = Messages.list_recent_messages(session1.id, 10)
      assert Enum.any?(messages, fn m -> m.body == "FAB message" end)
    end

    test "config_guide_open_chat subscribes to session", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "config_guide_open_chat", %{"session_id" => to_string(session1.id)})

      assert view_assigns(view).config_guide_active_session_id == session1.id

      topic = "session:#{session1.id}"

      subscribers =
        Registry.lookup(EyeInTheSky.PubSub, topic)
        |> Enum.map(fn {pid, _} -> pid end)

      assert view.pid in subscribers
    end

    test "config_guide_send_message saves message to DB", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "config_guide_send_message", %{
        "session_id" => to_string(session1.id),
        "body" => "Config message"
      })

      messages = Messages.list_recent_messages(session1.id, 10)
      assert Enum.any?(messages, fn m -> m.body == "Config message" end)
    end

    test "config_guide_close_chat unsubscribes from session", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "config_guide_open_chat", %{"session_id" => to_string(session1.id)})
      assert view_assigns(view).config_guide_active_session_id == session1.id

      render_hook(view, "config_guide_close_chat", %{})

      assert view_assigns(view).config_guide_active_session_id == nil

      topic = "session:#{session1.id}"

      subscribers =
        Registry.lookup(EyeInTheSky.PubSub, topic)
        |> Enum.map(fn {pid, _} -> pid end)

      assert view.pid not in subscribers
    end

    test "new agent message is routed while FAB chat is open", %{
      conn: conn,
      session1: session1
    } do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "fab_open_chat", %{"session_id" => to_string(session1.id)})
      assert view_assigns(view).fab_active_session_id == session1.id

      {:ok, msg} =
        Messages.send_message(%{
          session_id: session1.id,
          sender_role: "agent",
          recipient_role: "user",
          provider: "claude",
          body: "Agent response"
        })

      EyeInTheSky.Events.session_new_message(session1.id, msg)
      render(view)

      # Session should still be active after the broadcast
      assert view_assigns(view).fab_active_session_id == session1.id
    end

    test "handles empty bookmarks list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/chat")

      render_hook(view, "fab_set_bookmarks", %{"bookmarks" => []})

      assigns = view_assigns(view)
      assert assigns.fab_bookmarks == []
      assert assigns.fab_statuses == %{}
    end

    test "handles multiple bookmarks and populates statuses map", %{
      conn: conn,
      session1: session1,
      session2: session2
    } do
      {:ok, view, _html} = live(conn, "/chat")

      bookmarks = [bookmark(session1), bookmark(session2)]
      render_hook(view, "fab_set_bookmarks", %{"bookmarks" => bookmarks})

      statuses = view_assigns(view).fab_statuses
      assert Map.size(statuses) >= 2
    end
  end
end
