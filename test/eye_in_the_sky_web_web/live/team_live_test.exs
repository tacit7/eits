defmodule EyeInTheSkyWebWeb.TeamLive.IndexTest do
  use EyeInTheSkyWebWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "mobile_view assign" do
    test "mounts with mobile_view :list", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/teams")
      assert render(lv) =~ "Teams"
    end
  end
end
