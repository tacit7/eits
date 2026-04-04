defmodule EyeInTheSkyWeb.SessionLive.IndexTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Agents, Factory}

  defp setup_session(_) do
    agent = Factory.create_agent()
    session = Factory.create_session(agent)
    %{agent: agent, session: session}
  end

  describe "handle_info :agent_updated — payload shape handling" do
    setup [:setup_session]

    # Session struct payload (emitted by session_updated/session_started):
    # id == session_id — targeted row update should fire.
    test "Session struct payload refreshes the row", %{conn: conn, session: session} do
      {:ok, lv, _html} = live(conn, ~p"/sessions")

      send(lv.pid, {:agent_updated, session})
      html = render(lv)

      assert html =~ session.name
    end

    # Agent struct payload — real shape emitted by Agents.update_agent/2 via
    # Events.agent_updated/1. The Agent changeset never casts session_id, so
    # agent.session_id is always nil. Handler must fall back to full reload
    # instead of trying to use agent.id as a session_id.
    test "Agent struct payload (real Agents.update_agent shape) triggers reload without crash",
         %{conn: conn, agent: agent, session: session} do
      {:ok, lv, _html} = live(conn, ~p"/sessions")

      # Trigger via real update_agent path — broadcasts Agent struct with session_id: nil
      {:ok, _updated} = Agents.update_agent(agent, %{description: "updated description"})

      html = render(lv)

      # View must stay alive and show the session after the reload
      assert html =~ session.name
    end

    # Guard: agent.id must not accidentally equal session.id — if they matched
    # using payload.id would give a false positive. Verify they differ so the
    # test above proves the correct code path.
    test "agent.id and session.id differ in fixture", %{agent: agent, session: session} do
      assert agent.id != session.id
    end

    test "modal stays open when Agent struct payload arrives mid-form", %{
      conn: conn,
      agent: agent
    } do
      {:ok, lv, _html} = live(conn, ~p"/sessions")

      # Open the modal
      lv |> element("button", "New Agent") |> render_click()
      assert has_element?(lv, "textarea[name='description']")

      # Simulate agent_updated via real update path
      {:ok, _} = Agents.update_agent(agent, %{description: "mid-form update"})
      render(lv)

      # Modal must still be open
      assert has_element?(lv, "textarea[name='description']")
    end

    test "Session struct payload keeps modal open", %{conn: conn, session: session} do
      {:ok, lv, _html} = live(conn, ~p"/sessions")

      lv |> element("button", "New Agent") |> render_click()
      assert has_element?(lv, "textarea[name='description']")

      send(lv.pid, {:agent_updated, session})
      render(lv)

      assert has_element?(lv, "textarea[name='description']")
    end
  end
end
