defmodule EyeInTheSkyWeb.DmLive.TimerTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Factory
  alias EyeInTheSky.OrchestratorTimers

  setup %{user: _user} do
    agent = Factory.create_agent()
    session = Factory.create_session(agent)
    {:ok, agent: agent, session: session}
  end

  test "hamburger menu contains all action items", %{conn: conn, session: session} do
    {:ok, _view, html} = live(conn, "/dm/#{session.uuid}")
    assert html =~ "Reload"
    assert html =~ "Export"
    assert html =~ "Notify"
    assert html =~ "Schedule Message"
    refute html =~ "Cancel Schedule"
  end

  test "Cancel Schedule appears when active timer exists on mount", %{conn: conn, session: session} do
    OrchestratorTimers.schedule_once(session.id, 60_000)
    {:ok, _view, html} = live(conn, "/dm/#{session.uuid}")
    assert html =~ "Cancel Schedule"
  after
    OrchestratorTimers.cancel(session.id)
  end

  test "Cancel Schedule not shown when no timer on mount", %{conn: conn, session: session} do
    OrchestratorTimers.cancel(session.id)
    {:ok, _view, html} = live(conn, "/dm/#{session.uuid}")
    refute html =~ "Cancel Schedule"
  end

  test "schedule_timer event closes modal and activates timer badge", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, "/dm/#{session.uuid}")

    view |> element("#dm-actions-menu button[phx-click='open_schedule_timer']") |> render_click()
    assert render(view) =~ "Schedule Message"

    view
    |> element("button[phx-click='schedule_timer'][phx-value-mode='once'][phx-value-preset='5m']")
    |> render_click()

    html = render(view)
    refute html =~ "modal-open"
    assert html =~ "hero-clock"
  after
    OrchestratorTimers.cancel(session.id)
  end

  test "cancel_timer event removes timer display", %{conn: conn, session: session} do
    OrchestratorTimers.schedule_once(session.id, 60_000)
    {:ok, view, _html} = live(conn, "/dm/#{session.uuid}")
    assert render(view) =~ "Cancel Schedule"

    view |> element("#dm-actions-menu button[phx-click='cancel_timer']") |> render_click()

    html = render(view)
    refute html =~ "Cancel Schedule"
  end

  test "active timer badge shown after remount", %{conn: conn, session: session} do
    OrchestratorTimers.schedule_once(session.id, 60_000)
    {:ok, _view, html} = live(conn, "/dm/#{session.uuid}")
    assert html =~ "hero-clock"
  after
    OrchestratorTimers.cancel(session.id)
  end
end
