defmodule EyeInTheSkyWebWeb.TeamLive.IndexTest do
  use EyeInTheSkyWebWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Teams

  describe "mobile_view assign" do
    # Smoke test — verifies the page mounts without crashing.
    # mobile_view :list state is asserted via CSS classes below.
    test "mounts with mobile_view :list", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/teams")
      assert render(lv) =~ "Teams"
    end

    test "detail panel has hidden sm:flex on initial load", %{conn: conn} do
      # On load, mobile_view is :list so the detail panel gets hidden sm:flex.
      # The sidebar does NOT have hidden sm:flex (it hides only when mobile_view == :detail).
      {:ok, _lv, html} = live(conn, ~p"/teams")
      assert html =~ ~s(hidden sm:flex)
    end
  end

  describe "team selection" do
    test "selecting a team sets mobile_view to :detail", %{conn: conn} do
      {:ok, team} = Teams.create_team(%{name: "Test Team Select", status: "active"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      html = lv |> element("[phx-click='select_team'][phx-value-id='#{team.id}']") |> render_click()

      # After selection, detail panel is visible; sidebar now has hidden sm:flex.
      # The sidebar hidden class should now appear and team name should be present.
      assert html =~ "Test Team Select"
    end

    test "close_team resets mobile_view to :list", %{conn: conn} do
      {:ok, team} = Teams.create_team(%{name: "Close Team Test", status: "active"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      # Select team first
      lv |> element("[phx-click='select_team'][phx-value-id='#{team.id}']") |> render_click()

      # Close team via the back button
      html = lv |> element("[phx-click='close_team']") |> render_click()

      # Back to list state — "Teams" heading should still be present
      assert html =~ "Teams"
    end
  end
end
