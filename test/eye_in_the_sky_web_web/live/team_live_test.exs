defmodule EyeInTheSkyWebWeb.TeamLive.IndexTest do
  use EyeInTheSkyWebWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "mobile_view assign" do
    # Smoke test — verifies the page mounts without crashing.
    # mobile_view :list state is asserted in template tests (Chunk 2).
    test "mounts with mobile_view :list", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/teams")
      assert render(lv) =~ "Teams"
    end
  end
end
