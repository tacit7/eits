defmodule EyeInTheSkyWeb.Api.V1.NotificationControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Accounts.ApiKey

  defp uniq, do: System.unique_integer([:positive])

  setup %{conn: _conn} do
    token = "test_api_key_#{uniq()}"
    {:ok, _} = ApiKey.create(token, "test")
    conn = Phoenix.ConnTest.build_conn() |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    {:ok, conn: conn}
  end

  describe "POST /api/v1/notifications" do
    test "creates a notification with valid params", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/notifications", %{"title" => "Test #{uniq()}"})
      resp = json_response(conn, 200)
      assert resp["success"] == true
      assert resp["id"]
    end

    test "returns 400 when title is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/notifications", %{})
      resp = json_response(conn, 400)
      assert resp["success"] == false
      assert resp["message"] =~ "title is required"
    end

    test "returns 400 when title is empty string", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/notifications", %{"title" => ""})
      resp = json_response(conn, 400)
      assert resp["success"] == false
    end

    test "changeset error response uses sanitized message, not raw inspect", %{conn: conn} do
      # Force a changeset error — e.g. category too long (over DB varchar limit or validation)
      # The controller must NOT expose inspect(cs.errors) in the response body
      conn =
        post(conn, ~p"/api/v1/notifications", %{
          "title" => "Test #{uniq()}",
          "category" => String.duplicate("a", 300)
        })

      body = response(conn, conn.status)
      # Must never contain raw Elixir inspect output like [{:field, {"msg", []}}]
      refute body =~ ~r/\[.*:\w+.*\{.*\}\]/
      refute body =~ "#Ecto"
      refute body =~ "Ecto.Changeset"

      if conn.status == 422 do
        resp = json_response(conn, 422)
        assert resp["success"] == false
        assert resp["message"] == "Invalid notification data"
        assert is_map(resp["errors"])
      end
    end
  end
end
