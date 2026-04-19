defmodule EyeInTheSkyWeb.Live.CanvasLayoutTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "canvas index renders minimal layout without sidebar", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/canvases")

    refute html =~ "app-sidebar"
    assert html =~ "hero-chevron-left"
    assert html =~ "command-palette"
  end

  test "canvas show renders minimal layout without sidebar", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/canvases/999")

    refute html =~ "app-sidebar"
    assert html =~ "hero-chevron-left"
    assert html =~ "command-palette"
  end

  test "back button has fallback navigation", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/canvases")

    assert html =~ "history.length"
  end
end
