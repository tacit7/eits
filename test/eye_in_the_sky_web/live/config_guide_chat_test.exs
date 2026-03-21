defmodule EyeInTheSkyWeb.Live.ConfigGuideChatTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Agents, Sessions}

  setup do
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        status: "working"
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Config Guide Test",
        provider: "claude",
        status: "working",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    %{session: session}
  end

  test "config_guide_open_chat pushes history for valid session", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, ~p"/config")

    view |> render_hook("config_guide_open_chat", %{"session_id" => session.uuid})

    assert_push_event(view, "config_guide_history", %{messages: messages})
    assert is_list(messages)
  end

  test "config_guide_open_chat pushes error for unknown session", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/config")

    view |> render_hook("config_guide_open_chat", %{"session_id" => Ecto.UUID.generate()})

    assert_push_event(view, "config_guide_error", %{error: _})
  end

  test "config_guide_close_chat does not crash when no session is active", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/config")
    # Should not raise
    view |> render_hook("config_guide_close_chat", %{})
  end

  test "config_guide_open_chat then close_chat allows re-opening", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, ~p"/config")

    view |> render_hook("config_guide_open_chat", %{"session_id" => session.uuid})
    assert_push_event(view, "config_guide_history", %{})

    view |> render_hook("config_guide_close_chat", %{})
    # After close, re-opening should work (assign reset, not stale)
    view |> render_hook("config_guide_open_chat", %{"session_id" => session.uuid})
    assert_push_event(view, "config_guide_history", %{})
  end

  test "incoming message on config guide session routes to config_guide_message", %{
    conn: conn,
    session: session
  } do
    {:ok, view, _html} = live(conn, ~p"/config")

    # Open the config guide chat -- this subscribes the LiveView to "session:<id>"
    view |> render_hook("config_guide_open_chat", %{"session_id" => session.uuid})
    assert_push_event(view, "config_guide_history", %{})

    # Build a fake Message struct matching the pattern the handler expects
    msg = %EyeInTheSky.Messages.Message{
      id: 999,
      session_id: session.id,
      body: "Hello from agent",
      sender_role: "assistant",
      inserted_at: ~U[2026-03-15 12:00:00Z]
    }

    # Simulate the PubSub broadcast that the real system would send
    send(view.pid, {:new_message, msg})

    # Should push config_guide_message, NOT fab_chat_message
    assert_push_event(view, "config_guide_message", %{
      body: "Hello from agent",
      sender_role: "assistant"
    })
  end

  test "incoming message on config guide session does NOT emit fab_chat_message", %{
    conn: conn,
    session: session
  } do
    {:ok, view, _html} = live(conn, ~p"/config")

    view |> render_hook("config_guide_open_chat", %{"session_id" => session.uuid})
    assert_push_event(view, "config_guide_history", %{})

    msg = %EyeInTheSky.Messages.Message{
      id: 1000,
      session_id: session.id,
      body: "Test message",
      sender_role: "assistant",
      inserted_at: ~U[2026-03-15 12:00:00Z]
    }

    send(view.pid, {:new_message, msg})

    # Positional timeout -- refute_push_event does not accept keyword options
    refute_push_event(view, "fab_chat_message", %{}, 100)
  end
end
