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

  describe "tab routing" do
    test "renders tab bar with all 6 tabs", %{conn: conn} do
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings")
      assert html =~ "General"
      assert html =~ "Editor"
      assert html =~ "Auth &amp; Keys"
      assert html =~ "Workflow"
      assert html =~ "Pricing"
      assert html =~ "System"
    end

    test "defaults to general tab showing Default Model", %{conn: conn} do
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings")
      assert html =~ "Default Model"
    end

    test "?tab=auth loads auth tab", %{conn: conn} do
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings?tab=auth")
      assert html =~ "API Keys"
    end

    test "?tab=workflow loads workflow tab", %{conn: conn} do
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings?tab=workflow")
      assert html =~ "EITS Workflow"
    end

    test "unknown tab falls back to general and shows Default Model", %{conn: conn} do
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings?tab=nonexistent")
      assert html =~ "Default Model"
    end
  end

  describe "auth tab" do
    test "renders API Keys section", %{conn: conn} do
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings?tab=auth")
      assert html =~ "Anthropic API Key"
      assert html =~ "EITS REST API Key"
    end

    test "regenerate button shows generated key", %{conn: conn} do
      {:ok, lv, _html} = live(auth_conn(conn), ~p"/settings?tab=auth")
      html = lv |> element("button", "Regenerate") |> render_click()
      assert html =~ "Copy this key now"
      assert html =~ "EITS_API_KEY"
    end
  end

  describe "workflow tab" do
    test "renders EITS Workflow toggle", %{conn: conn} do
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings?tab=workflow")
      assert html =~ "EITS Workflow"
      assert html =~ ~s(phx-value-key="eits_workflow_enabled")
    end
  end

  describe "editor tab" do
    test "renders preferred editor selector with VS Code option", %{conn: conn} do
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings?tab=editor")
      assert html =~ "Preferred Editor"
      assert html =~ "VS Code"
    end

    test "renders custom command input", %{conn: conn} do
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings?tab=editor")
      assert html =~ "Custom Command"
    end
  end
end
