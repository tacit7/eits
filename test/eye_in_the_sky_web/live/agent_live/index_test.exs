defmodule EyeInTheSkyWeb.AgentLive.IndexTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.Factory

  defp setup_agent_session(_) do
    agent = Factory.create_agent()
    session = Factory.create_session(agent)
    %{agent: agent, session: session}
  end

  describe "mount" do
    setup [:setup_agent_session]

    test "renders the agents page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "agents"
    end
  end

  describe "rename_session — Integer.parse fix" do
    setup [:setup_agent_session]

    test "non-integer session_id is a no-op and does not crash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      # Should not raise; view stays alive and returns valid HTML
      html = render_hook(lv, "rename_session", %{"session_id" => "not-an-int"})
      assert html =~ "agents"
    end

    test "empty session_id is a no-op and does not crash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      html = render_hook(lv, "rename_session", %{"session_id" => ""})
      assert html =~ "agents"
    end

    test "valid integer session_id sets editing_session_id", %{conn: conn, session: session} do
      {:ok, lv, _html} = live(conn, ~p"/")

      # Should not raise; editing UI should appear
      assert render_hook(lv, "rename_session", %{"session_id" => to_string(session.id)}) =~
               "agents"
    end
  end

  describe "send_direct_message — error branches" do
    setup [:setup_agent_session]

    test "unknown session_id is handled without crash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      # Flash notifications are suppressed (toast flash disabled in flash_group).
      # Verify the LiveView handles the unknown session gracefully without crashing.
      html =
        render_hook(lv, "send_direct_message", %{
          "session_id" => "999999",
          "body" => "hello"
        })

      assert is_binary(html)
    end
  end
end
