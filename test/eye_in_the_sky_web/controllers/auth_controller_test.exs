defmodule EyeInTheSkyWeb.AuthControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  alias EyeInTheSky.Auth.WebAuthnHelpers

  # Build a minimal conn with no login (auth endpoints are unauthenticated)
  setup do
    conn = Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})
    {:ok, conn: conn}
  end

  # ---------------------------------------------------------------------------
  # register_complete — Bug 1: malformed base64url for params["id"] returns 400
  # ---------------------------------------------------------------------------

  describe "register_complete/2 — malformed base64url input" do
    test "returns 400 (not 500) when params[id] is invalid base64url", %{conn: conn} do
      # Plant a challenge and username in the session to get past the early guards
      challenge = Wax.new_registration_challenge(trusted_attestation_types: [:none, :self])
      serialized = WebAuthnHelpers.serialize_challenge(challenge)

      conn =
        conn
        |> Plug.Conn.put_session(:webauthn_challenge, serialized)
        |> Plug.Conn.put_session(:webauthn_username, "alice")
        |> Plug.Conn.put_session(:webauthn_reg_token, "tok")

      conn =
        post(conn, ~p"/auth/register/complete", %{
          "attestationObject" => Base.url_encode64("fake", padding: false),
          "clientDataJSON" => Base.url_encode64("fake", padding: false),
          "id" => "!!!not-valid-base64url!!!"
        })

      # Must be a 4xx, never a 500
      assert conn.status in [400, 422]
      refute conn.status == 500
    end

    test "returns 400 when params[id] is nil", %{conn: conn} do
      challenge = Wax.new_registration_challenge(trusted_attestation_types: [:none, :self])
      serialized = WebAuthnHelpers.serialize_challenge(challenge)

      conn =
        conn
        |> Plug.Conn.put_session(:webauthn_challenge, serialized)
        |> Plug.Conn.put_session(:webauthn_username, "alice")
        |> Plug.Conn.put_session(:webauthn_reg_token, "tok")

      conn =
        post(conn, ~p"/auth/register/complete", %{
          "attestationObject" => Base.url_encode64("fake", padding: false),
          "clientDataJSON" => Base.url_encode64("fake", padding: false)
          # "id" intentionally omitted
        })

      assert conn.status in [400, 422]
      refute conn.status == 500
    end
  end

  # ---------------------------------------------------------------------------
  # register_complete — Bug 2: challenge is consumed (cannot be replayed)
  # ---------------------------------------------------------------------------

  describe "register_complete/2 — challenge single-use" do
    test "challenge is removed from session after first read", %{conn: conn} do
      challenge = Wax.new_registration_challenge(trusted_attestation_types: [:none, :self])
      serialized = WebAuthnHelpers.serialize_challenge(challenge)

      conn =
        conn
        |> Plug.Conn.put_session(:webauthn_challenge, serialized)
        |> Plug.Conn.put_session(:webauthn_username, "alice")
        |> Plug.Conn.put_session(:webauthn_reg_token, "tok")

      # First attempt — will fail WebAuthn verification but the challenge must
      # be consumed regardless.
      conn1 =
        post(conn, ~p"/auth/register/complete", %{
          "attestationObject" => Base.url_encode64("fake", padding: false),
          "clientDataJSON" => Base.url_encode64("fake", padding: false),
          "id" => Base.url_encode64("fake-id", padding: false)
        })

      # Extract the session from the response conn and verify challenge is gone.
      assert Plug.Conn.get_session(conn1, :webauthn_challenge) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # login_complete — Bug 2: challenge consumed even on WebAuthn failure
  # ---------------------------------------------------------------------------

  describe "login_complete/2 — challenge single-use" do
    test "challenge is removed from session after first read even on auth failure", %{conn: conn} do
      challenge = Wax.new_authentication_challenge(trusted_attestation_types: [:none, :self])
      serialized = WebAuthnHelpers.serialize_challenge(challenge)

      conn =
        conn
        |> Plug.Conn.put_session(:webauthn_challenge, serialized)
        |> Plug.Conn.put_session(:webauthn_user_id, 1)

      conn1 =
        post(conn, ~p"/auth/login/complete", %{
          "id" => Base.url_encode64("cred-id", padding: false),
          "authenticatorData" => Base.url_encode64("fake", padding: false),
          "signature" => Base.url_encode64("fake", padding: false),
          "clientDataJSON" => Base.url_encode64("fake", padding: false)
        })

      # Must have been cleared even though auth failed
      assert Plug.Conn.get_session(conn1, :webauthn_challenge) == nil
    end

    test "returns 401 when no challenge is in session", %{conn: conn} do
      # No session setup — simulates a replayed or stale request
      conn =
        post(conn, ~p"/auth/login/complete", %{
          "id" => Base.url_encode64("cred-id", padding: false),
          "authenticatorData" => Base.url_encode64("fake", padding: false),
          "signature" => Base.url_encode64("fake", padding: false),
          "clientDataJSON" => Base.url_encode64("fake", padding: false)
        })

      # no_challenge maps to {:error, :no_challenge} → 401 unauthorized
      assert conn.status in [400, 401, 422]
    end
  end

  # ---------------------------------------------------------------------------
  # register_challenge — basic guards
  # ---------------------------------------------------------------------------

  describe "register_challenge/2" do
    test "returns 400 when token param is missing", %{conn: conn} do
      conn = post(conn, ~p"/auth/register/challenge", %{})
      assert conn.status == 400
      assert json_response(conn, 400)["error"] == "registration token required"
    end

    test "returns 400 when token param is empty string", %{conn: conn} do
      conn = post(conn, ~p"/auth/register/challenge", %{"token" => ""})
      assert conn.status == 400
    end
  end

  # ---------------------------------------------------------------------------
  # login_challenge — basic guards
  # ---------------------------------------------------------------------------

  describe "login_challenge/2" do
    test "returns 400 when username param is missing", %{conn: conn} do
      conn = post(conn, ~p"/auth/login/challenge", %{})
      assert conn.status == 400
      assert json_response(conn, 400)["error"] == "username is required"
    end
  end
end
