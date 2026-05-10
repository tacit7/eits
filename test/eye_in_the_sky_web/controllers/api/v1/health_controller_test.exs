defmodule EyeInTheSkyWeb.Api.V1.HealthControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  describe "GET /api/v1/health" do
    test "returns 200 with healthy status payload", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/health")

      assert json_response(conn, 200) == %{
               "ok" => true,
               "status" => "healthy"
             }
    end

    test "responds with application/json content-type", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/health")

      assert ["application/json" <> _] = get_resp_header(conn, "content-type")
    end

    test "ignores query params", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/health?foo=bar&baz=qux")

      assert json_response(conn, 200) == %{
               "ok" => true,
               "status" => "healthy"
             }
    end

    test "is idempotent across repeated calls", %{conn: conn} do
      response1 = conn |> get(~p"/api/v1/health") |> json_response(200)
      response2 = build_conn() |> get(~p"/api/v1/health") |> json_response(200)

      assert response1 == response2
    end
  end
end
