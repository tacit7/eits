defmodule EyeInTheSkyWeb.SessionLive.IndexTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.Factory

  defp setup_session(_) do
    agent = Factory.create_agent()
    session = Factory.create_session(agent)
    %{agent: agent, session: session}
  end

  describe "handle_info :agent_updated — payload shape handling" do
    setup [:setup_session]

    # Session struct payload: id == session_id (emitted by session_updated/session_started)
    test "Session payload refreshes the row", %{conn: conn, session: session} do
      {:ok, lv, _html} = live(conn, ~p"/sessions")

      send(lv.pid, {:agent_updated, session})
      html = render(lv)

      assert html =~ session.name
    end

    # Agent struct payload: id == agent_id, session_id is the linked session
    # This is the shape emitted by Events.agent_updated/1 (events.ex:153)
    test "Agent payload uses session_id field, not agent id", %{
      conn: conn,
      agent: agent,
      session: session
    } do
      {:ok, lv, _html} = live(conn, ~p"/sessions")

      # Simulate the Agent struct shape: id is agent.id, session_id is session.id
      # These must differ to prove the handler uses session_id not id
      assert agent.id != session.id

      agent_payload = %{id: agent.id, session_id: session.id}
      send(lv.pid, {:agent_updated, agent_payload})
      html = render(lv)

      assert html =~ session.name
    end

    # Guard: agent.id must not accidentally equal session.id in the test above.
    # If they're equal the test proves nothing. This test documents the contract
    # by verifying the view still functions when agent.id would have been wrong.
    test "Agent payload with nil session_id falls back to reload", %{conn: conn, agent: agent} do
      {:ok, lv, _html} = live(conn, ~p"/sessions")

      # Agent with no linked session — session_id is nil, id is agent.id
      agent_no_session = %{id: agent.id, session_id: nil}
      send(lv.pid, {:agent_updated, agent_no_session})
      html = render(lv)

      # View should stay alive (full reload ran without crash)
      assert html =~ "sessions"
    end

    test "modal stays open when Agent payload arrives mid-form", %{
      conn: conn,
      agent: agent,
      session: session
    } do
      {:ok, lv, _html} = live(conn, ~p"/sessions")

      # Open the modal
      lv |> element("button", "New Agent") |> render_click()
      assert has_element?(lv, "textarea[name='description']")

      # Simulate an agent_updated Agent payload arriving while form is open
      agent_payload = %{id: agent.id, session_id: session.id}
      send(lv.pid, {:agent_updated, agent_payload})
      render(lv)

      # Modal must still be open
      assert has_element?(lv, "textarea[name='description']")
    end
  end
end
