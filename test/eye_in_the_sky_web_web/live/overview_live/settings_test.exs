defmodule EyeInTheSkyWebWeb.OverviewLive.SettingsTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Accounts

  defp create_user do
    {:ok, user} = Accounts.get_or_create_user("test-settings-user")
    user
  end

  defp auth_conn(conn) do
    user = create_user()
    conn |> init_test_session(%{"user_id" => user.id})
  end

  describe "settings page" do
    test "mounts without crashing", %{conn: conn} do
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings")
      assert html =~ "Settings"
    end
  end
end
