defmodule EyeInTheSkyWeb.Api.V1.PushControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  # ConnCase sets up an authenticated conn by default (user_id + valid session_token).

  defp unauthenticated_conn do
    Phoenix.ConnTest.build_conn()
    |> Plug.Test.init_test_session(%{})
  end

  defp expired_session_conn(user) do
    Phoenix.ConnTest.build_conn()
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:session_token, "invalid_or_expired_token")
  end

  # ---- GET /api/v1/push/vapid-public-key ----

  describe "GET /api/v1/push/vapid-public-key" do
    test "returns 401 JSON with no session", %{} do
      conn = get(unauthenticated_conn(), "/api/v1/push/vapid-public-key")
      assert conn.status == 401
      assert conn.resp_headers |> List.keyfind("content-type", 0) |> elem(1) =~ "application/json"
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end

    test "returns 401 JSON with invalid session_token", %{user: user} do
      conn = get(expired_session_conn(user), "/api/v1/push/vapid-public-key")
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end

    test "returns vapid public key for authenticated session", %{conn: conn} do
      conn = get(conn, "/api/v1/push/vapid-public-key")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "public_key")
    end
  end

  # ---- POST /api/v1/push/subscribe ----

  describe "POST /api/v1/push/subscribe" do
    test "returns 401 JSON with no session", %{} do
      conn =
        post(unauthenticated_conn(), "/api/v1/push/subscribe", %{
          "endpoint" => "https://example.com/push/1",
          "keys" => %{"auth" => "auth123", "p256dh" => "key123"}
        })

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end

    test "returns 401 JSON with invalid session_token", %{user: user} do
      conn =
        post(expired_session_conn(user), "/api/v1/push/subscribe", %{
          "endpoint" => "https://example.com/push/2",
          "keys" => %{"auth" => "auth123", "p256dh" => "key123"}
        })

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end

    test "accepts subscription from authenticated session", %{conn: conn} do
      conn =
        post(conn, "/api/v1/push/subscribe", %{
          "endpoint" => "https://example.com/push/#{System.unique_integer([:positive])}",
          "keys" => %{"auth" => "dGVzdA", "p256dh" => "dGVzdA"}
        })

      # Controller returns 200 on success or 422 on validation error — not 401 or 302
      assert conn.status in [200, 422]
      assert conn.resp_headers |> List.keyfind("content-type", 0) |> elem(1) =~ "application/json"
    end
  end

  # ---- DELETE /api/v1/push/subscribe ----

  describe "DELETE /api/v1/push/subscribe" do
    test "returns 401 JSON with no session", %{} do
      conn =
        delete(unauthenticated_conn(), "/api/v1/push/subscribe", %{
          "endpoint" => "https://example.com/push/1"
        })

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end

    test "returns 401 JSON with invalid session_token", %{user: user} do
      conn =
        delete(expired_session_conn(user), "/api/v1/push/subscribe", %{
          "endpoint" => "https://example.com/push/1"
        })

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end

    test "accepts unsubscribe from authenticated session", %{conn: conn} do
      conn =
        delete(conn, "/api/v1/push/subscribe", %{
          "endpoint" => "https://example.com/push/nonexistent"
        })

      # Controller returns 200 even when endpoint doesn't exist (idempotent delete)
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"success" => true}
    end
  end
end
