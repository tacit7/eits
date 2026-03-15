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

    test "detail panel has hidden sm:block on initial load", %{conn: conn} do
      # On load, mobile_view is :list so the detail panel gets hidden sm:block.
      # The sidebar does NOT have hidden sm:block (it hides only when mobile_view == :detail).
      {:ok, _lv, html} = live(conn, ~p"/teams")
      assert html =~ ~s(hidden sm:block)
    end
  end

  describe "team selection" do
    test "selecting a team sets mobile_view to :detail", %{conn: conn} do
      {:ok, team} = Teams.create_team(%{name: "Test Team Select", status: "active"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      html = lv |> element("[phx-click='select_team'][phx-value-id='#{team.id}']") |> render_click()

      # Team name visible in detail view
      assert html =~ "Test Team Select"
      # Back button visible on mobile (proves mobile_view: :detail state)
      assert html =~ ~s(phx-click="close_team")
    end

    test "close_team resets mobile_view to :list", %{conn: conn} do
      {:ok, team} = Teams.create_team(%{name: "Close Team Test", status: "active"})

      {:ok, lv, _html} = live(conn, ~p"/teams")

      # Select team first
      lv |> element("[phx-click='select_team'][phx-value-id='#{team.id}']") |> render_click()

      # Close team via the back button
      html = lv |> element("[phx-click='close_team']") |> render_click()

      # Back to list state — detail panel should be hidden again (mobile_view: :list)
      assert html =~ ~s(hidden sm:block)
      # Back button gone (mobile_view: :list means no back button)
      refute html =~ ~s(phx-click="close_team")
    end
  end
end
