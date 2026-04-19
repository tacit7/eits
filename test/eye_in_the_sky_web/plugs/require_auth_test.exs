defmodule EyeInTheSkyWeb.Plugs.RequireAuthTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  alias EyeInTheSky.Accounts.ApiKey
  alias EyeInTheSkyWeb.Plugs.RequireAuth

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp call_plug(conn) do
    RequireAuth.call(conn, RequireAuth.init([]))
  end

  defp bearer_conn(token) do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  defp uniq, do: System.unique_integer([:positive])

  # ---------------------------------------------------------------------------
  # Missing / malformed authorization header
  # ---------------------------------------------------------------------------

  describe "no authorization header" do
    test "returns 401 JSON" do
      conn = call_plug(Phoenix.ConnTest.build_conn())
      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end
  end

  describe "malformed authorization header" do
    test "returns 401 when header is not 'Bearer <token>'" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "Basic dXNlcjpwYXNz")
        |> call_plug()

      assert conn.halted
      assert conn.status == 401
    end

    test "returns 401 when header is 'Bearer' with no token" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer")
        |> call_plug()

      assert conn.halted
      assert conn.status == 401
    end

    test "returns 401 when authorization header value is empty string" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "")
        |> call_plug()

      assert conn.halted
      assert conn.status == 401
    end
  end

  # ---------------------------------------------------------------------------
  # Invalid / unknown tokens
  # ---------------------------------------------------------------------------

  describe "invalid bearer token" do
    test "returns 401 for a random unknown token" do
      conn = bearer_conn("not_a_real_token_#{uniq()}") |> call_plug()
      assert conn.halted
      assert conn.status == 401
    end

    test "returns 401 for a token that was never registered" do
      conn = bearer_conn("completely_fake_#{uniq()}") |> call_plug()
      assert conn.halted
      assert conn.status == 401
    end
  end

  # ---------------------------------------------------------------------------
  # Valid DB token
  # ---------------------------------------------------------------------------

  describe "valid DB API key" do
    test "passes through when token matches an active DB key" do
      token = "valid_db_key_#{uniq()}"
      {:ok, _} = ApiKey.create(token, "test_label_#{uniq()}")
      conn = bearer_conn(token) |> call_plug()
      refute conn.halted
    end

    test "passes through for a key with nil valid_until (permanent key)" do
      token = "permanent_key_#{uniq()}"
      {:ok, _} = ApiKey.create(token, "permanent_#{uniq()}", nil)
      conn = bearer_conn(token) |> call_plug()
      refute conn.halted
    end
  end

  # ---------------------------------------------------------------------------
  # Expired DB token
  # ---------------------------------------------------------------------------

  describe "expired DB API key" do
    test "returns 401 for a key whose valid_until is in the past" do
      token = "expired_key_#{uniq()}"
      past = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
      {:ok, _} = ApiKey.create(token, "expired_#{uniq()}", past)
      conn = bearer_conn(token) |> call_plug()
      assert conn.halted
      assert conn.status == 401
    end
  end

  # ---------------------------------------------------------------------------
  # Env-var API key (legacy single-key mode)
  # ---------------------------------------------------------------------------

  describe "env-var configured API key" do
    setup do
      old = Application.get_env(:eye_in_the_sky, :api_key)
      on_exit(fn -> Application.put_env(:eye_in_the_sky, :api_key, old) end)
      :ok
    end

    test "passes through when bearer token matches the configured env key" do
      token = "env_key_#{uniq()}"
      Application.put_env(:eye_in_the_sky, :api_key, token)
      conn = bearer_conn(token) |> call_plug()
      refute conn.halted
    end

    test "returns 401 when bearer token does not match the env key" do
      Application.put_env(:eye_in_the_sky, :api_key, "correct_env_key_#{uniq()}")
      conn = bearer_conn("wrong_token_#{uniq()}") |> call_plug()
      assert conn.halted
      assert conn.status == 401
    end

    test "does not accept env key when it is nil (falls back to DB only)" do
      Application.put_env(:eye_in_the_sky, :api_key, nil)
      # A DB key should still work
      token = "db_fallback_#{uniq()}"
      {:ok, _} = ApiKey.create(token, "fallback_#{uniq()}")
      conn = bearer_conn(token) |> call_plug()
      refute conn.halted
    end

    test "does not accept env key when it is empty string" do
      Application.put_env(:eye_in_the_sky, :api_key, "")
      # Empty string env key must never authenticate
      conn = bearer_conn("") |> call_plug()
      assert conn.halted
      assert conn.status == 401
    end
  end

  # ---------------------------------------------------------------------------
  # Response shape
  # ---------------------------------------------------------------------------

  describe "401 response shape" do
    test "response content-type is application/json" do
      conn = Phoenix.ConnTest.build_conn() |> call_plug()
      assert Plug.Conn.get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    end

    test "response body is valid JSON with error key" do
      conn = Phoenix.ConnTest.build_conn() |> call_plug()
      assert %{"error" => "unauthorized"} = Jason.decode!(conn.resp_body)
    end
  end
end
