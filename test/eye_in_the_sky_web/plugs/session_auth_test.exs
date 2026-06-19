defmodule EyeInTheSkyWeb.Plugs.SessionAuthTest do
  # async: false because we mutate Application env (:bypass_auth) in some tests.
  use ExUnit.Case, async: false
  use Plug.Test

  alias EyeInTheSkyWeb.Plugs.SessionAuth

  @session_opts Plug.Session.init(
                  store: :cookie,
                  key: "_session_auth_test",
                  signing_salt: "test-salt-12345",
                  encryption_salt: "test-encrypt-salt-12345"
                )

  # Build a conn that has the session machinery wired up so get_session/2 works.
  defp session_conn(session_data \\ %{}) do
    conn =
      conn(:get, "/admin")
      |> Map.put(:secret_key_base, String.duplicate("a", 64))
      |> Plug.Session.call(@session_opts)
      |> fetch_session()

    Enum.reduce(session_data, conn, fn {k, v}, acc -> put_session(acc, k, v) end)
  end

  setup do
    prior = Application.get_env(:eye_in_the_sky, :bypass_auth)
    on_exit(fn -> Application.put_env(:eye_in_the_sky, :bypass_auth, prior) end)
    Application.put_env(:eye_in_the_sky, :bypass_auth, false)
    :ok
  end

  describe "init/1" do
    test "returns opts unchanged" do
      assert SessionAuth.init([]) == []
      assert SessionAuth.init(foo: :bar) == [foo: :bar]
    end
  end

  describe "call/2 when bypass_auth is true" do
    test "passes through without checking session" do
      Application.put_env(:eye_in_the_sky, :bypass_auth, true)
      conn = session_conn() |> SessionAuth.call([])

      refute conn.halted
      assert conn.status == nil
    end

    test "passes through even without a fetched session" do
      Application.put_env(:eye_in_the_sky, :bypass_auth, true)
      # Plain conn with no session machinery — bypass should short-circuit before get_session.
      conn = conn(:get, "/admin") |> SessionAuth.call([])

      refute conn.halted
    end
  end

  describe "call/2 when bypass_auth is false" do
    test "redirects to /auth/login and halts when session has no user_id" do
      conn = session_conn() |> SessionAuth.call([])

      assert conn.halted
      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["/auth/login"]
      assert conn.resp_body == ""
    end

    test "redirects when user_id is explicitly nil" do
      conn = session_conn(%{user_id: nil}) |> SessionAuth.call([])

      assert conn.halted
      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["/auth/login"]
    end

    test "passes through when user_id is set in session" do
      conn = session_conn(%{user_id: 42}) |> SessionAuth.call([])

      refute conn.halted
      assert conn.status == nil
    end

    test "passes through with a string user_id" do
      conn = session_conn(%{user_id: "user-abc"}) |> SessionAuth.call([])

      refute conn.halted
    end
  end

  describe "call/2 when bypass_auth is unset" do
    test "defaults to enforcing auth (no user_id → redirect)" do
      Application.delete_env(:eye_in_the_sky, :bypass_auth)
      conn = session_conn() |> SessionAuth.call([])

      assert conn.halted
      assert conn.status == 302
    end
  end
end
