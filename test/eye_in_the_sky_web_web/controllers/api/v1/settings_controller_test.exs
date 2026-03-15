defmodule EyeInTheSkyWebWeb.Api.V1.SettingsControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  describe "GET /api/v1/settings/eits_workflow_enabled" do
    test "returns enabled: true by default", %{conn: conn} do
      EyeInTheSkyWeb.Settings.put("eits_workflow_enabled", "true")
      conn = get(conn, ~p"/api/v1/settings/eits_workflow_enabled")
      assert json_response(conn, 200) == %{"enabled" => true}
    end

    test "returns enabled: false when setting is false", %{conn: conn} do
      EyeInTheSkyWeb.Settings.put("eits_workflow_enabled", "false")
      on_exit(fn -> EyeInTheSkyWeb.Settings.put("eits_workflow_enabled", "true") end)
      conn = get(conn, ~p"/api/v1/settings/eits_workflow_enabled")
      assert json_response(conn, 200) == %{"enabled" => false}
    end

    test "does not require auth header", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/settings/eits_workflow_enabled")
      assert conn.status == 200
    end
  end
end
