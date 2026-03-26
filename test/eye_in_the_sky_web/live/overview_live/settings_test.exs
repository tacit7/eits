defmodule EyeInTheSkyWeb.OverviewLive.SettingsTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Accounts

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

  describe "theme settings" do
    test "renders theme buttons on general tab", %{conn: conn} do
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings")
      assert html =~ "Appearance"
      assert html =~ "Theme"
      for label <- ~w(Dark Light Latte Mocha Macchiato) do
        assert html =~ label
      end
      assert html =~ "Frappé"
    end

    test "set_theme persists theme to Settings", %{conn: conn} do
      {:ok, lv, _html} = live(auth_conn(conn), ~p"/settings")
      lv |> element(~s(button[phx-value-theme="mocha"]), "Mocha") |> render_click()
      assert EyeInTheSky.Settings.get("theme") == "mocha"
    end

    test "set_theme updates button active state", %{conn: conn} do
      {:ok, lv, _html} = live(auth_conn(conn), ~p"/settings")
      html = lv |> element(~s(button[phx-value-theme="latte"]), "Latte") |> render_click()
      assert html =~ ~s(btn-primary)
    end

    test "normalizes empty theme to dark on mount", %{conn: conn} do
      EyeInTheSky.Settings.put("theme", "")
      {:ok, _lv, html} = live(auth_conn(conn), ~p"/settings")
      assert EyeInTheSky.Settings.get("theme") == "dark"
      assert html =~ "Appearance"
    end
  end

  describe "root layout data-theme" do
    test "renders data-theme from Settings", %{conn: conn} do
      EyeInTheSky.Settings.put("theme", "macchiato")
      conn = auth_conn(conn) |> get(~p"/settings")
      assert html_response(conn, 200) =~ ~s(data-theme="macchiato")
    end

    test "defaults to dark when theme is nil", %{conn: conn} do
      EyeInTheSky.Settings.reset("theme")
      conn = auth_conn(conn) |> get(~p"/settings")
      assert html_response(conn, 200) =~ ~s(data-theme="dark")
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
