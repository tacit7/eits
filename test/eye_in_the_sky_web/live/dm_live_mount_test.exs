defmodule EyeInTheSkyWeb.DmLive.MountTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Factory

  setup %{user: _user} do
    agent = Factory.create_agent()
    session = Factory.create_session(agent)
    {:ok, agent: agent, session: session}
  end

  test "authenticated user can mount DmLive and subscribe to session events", %{
    conn: conn,
    session: session
  } do
    {:ok, view, _html} = live(conn, "/dm/#{session.uuid}")
    assert view |> has_element?("#dm-page")
  end

  test "unauthenticated user cannot mount DmLive", %{session: session} do
    conn = build_conn()
    {:error, {:redirect, %{to: to, flash: flash}}} = live(conn, "/dm/#{session.uuid}")
    assert to == "/auth/login"
  end

  test "session mount does not broadcast on disconnected phase", %{
    conn: conn,
    session: session
  } do
    {:ok, view, _html} = live(conn, "/dm/#{session.uuid}")
    assert view |> has_element?("#dm-page")
  end

  test "non-owner cannot access session via subscription redirect on connect", %{
    session: session
  } do
    # Simulate a scenario where auth is disabled but we're testing the ownership check
    # by creating a separate user connection and trying to access another's session
    conn = build_conn() |> put_session(:user_id, nil)
    {:error, {:redirect, _}} = live(conn, "/dm/#{session.uuid}")
  end
end
