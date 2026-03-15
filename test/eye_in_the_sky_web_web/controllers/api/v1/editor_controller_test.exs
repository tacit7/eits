defmodule EyeInTheSkyWebWeb.Api.V1.EditorControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  describe "POST /api/v1/editor/open" do
    setup %{conn: conn} do
      # Use echo as the editor — it exists everywhere and exits immediately
      EyeInTheSkyWeb.Settings.put("preferred_editor", "echo")
      on_exit(fn -> EyeInTheSkyWeb.Settings.put("preferred_editor", "code") end)
      # Auth: in test env EITS_API_KEY is typically unset so RequireAuth passes through
      {:ok, conn: put_req_header(conn, "content-type", "application/json")}
    end

    test "returns ok for valid path", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/editor/open", %{"path" => "/tmp/test.txt"})
      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "returns 422 for missing path", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/editor/open", %{})
      assert json_response(conn, 422) == %{"error" => "path is required"}
    end
  end
end
