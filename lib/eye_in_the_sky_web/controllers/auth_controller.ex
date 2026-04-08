defmodule EyeInTheSkyWeb.AuthController do
  use EyeInTheSkyWeb, :controller

  require Logger

  alias EyeInTheSky.Accounts
  alias EyeInTheSky.Auth.WebAuthnHelpers

  # --- Registration (token-gated) ---

  @doc "POST /auth/register/challenge — validate one-time token, return WebAuthn options"
  def register_challenge(conn, %{"token" => token}) when is_binary(token) and token != "" do
    case Accounts.peek_registration_token(token) do
      {:ok, username} ->
        wax_opts = webauthn_opts_for(conn)
        challenge = Wax.new_registration_challenge(wax_opts)

        rp_id = challenge.rp_id
        challenge_b64 = Base.url_encode64(challenge.bytes, padding: false)
        serialized = WebAuthnHelpers.serialize_challenge(challenge)

        conn
        |> put_session(:webauthn_challenge, serialized)
        |> put_session(:webauthn_username, username)
        |> put_session(:webauthn_reg_token, token)
        |> json(%{
          challenge: challenge_b64,
          rp: %{name: "Eye in the Sky", id: rp_id},
          user: %{
            id: Base.url_encode64(username, padding: false),
            name: username,
            displayName: username
          },
          pubKeyCredParams: [%{type: "public-key", alg: -7}, %{type: "public-key", alg: -257}],
          timeout: 60_000,
          attestation: "none",
          authenticatorSelection: %{
            residentKey: "preferred",
            requireResidentKey: false,
            userVerification: "preferred"
          }
        })

      {:error, :expired} ->
        conn |> put_status(:gone) |> json(%{error: "registration link has expired"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "invalid registration link"})
    end
  end

  def register_challenge(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "registration token required"})
  end

  @doc "POST /auth/register/complete — consume token, verify and store credential"
  def register_complete(conn, params) do
    with {:ok, challenge} <- pop_challenge(conn),
         username when not is_nil(username) <- get_session(conn, :webauthn_username),
         token when not is_nil(token) <- get_session(conn, :webauthn_reg_token),
         {:ok, ^username} <- Accounts.consume_registration_token(token),
         {:ok, attestation_object} <- decode_b64url(params["attestationObject"]),
         {:ok, client_data_json} <- decode_b64url(params["clientDataJSON"]),
         credential_id_raw <- decode_b64url!(params["id"]),
         {:ok, {auth_data, _attestation}} <-
           Wax.register(attestation_object, client_data_json, challenge) do
      cred_id = auth_data.attested_credential_data.credential_id
      cose_key = auth_data.attested_credential_data.credential_public_key
      cose_key_bin = :erlang.term_to_binary(cose_key)
      sign_count = auth_data.sign_count || 0

      with {:ok, user} <- Accounts.get_or_create_user(username),
           {:ok, _passkey} <-
             Accounts.create_passkey(%{
               user_id: user.id,
               credential_id: cred_id || credential_id_raw,
               cose_key: cose_key_bin,
               sign_count: sign_count
             }) do
        {:ok, session_token} = Accounts.create_user_session(user.id)

        conn
        |> configure_session(renew: true)
        |> delete_session(:webauthn_challenge)
        |> delete_session(:webauthn_username)
        |> delete_session(:webauthn_reg_token)
        |> put_session(:user_id, user.id)
        |> put_session(:session_token, session_token)
        |> json(%{ok: true})
      else
        {:error, reason} ->
          Logger.error("WebAuthn registration complete failed: #{inspect(reason)}")
          conn |> put_status(:unprocessable_entity) |> json(%{error: "Registration failed"})
      end
    else
      {:error, :expired} ->
        conn |> put_status(:gone) |> json(%{error: "registration link has expired"})

      {:error, reason} ->
        Logger.error("WebAuthn registration challenge failed: #{inspect(reason)}")
        conn |> put_status(:bad_request) |> json(%{error: "Registration failed"})

      nil ->
        conn |> put_status(:bad_request) |> json(%{error: "session expired"})
    end
  end

  # --- Authentication ---

  @doc "POST /auth/login/challenge — generate a WebAuthn authentication challenge"
  def login_challenge(conn, %{"username" => username})
      when is_binary(username) and username != "" do
    case Accounts.get_user_by_username(username) do
      nil ->
        # Return same error as "no passkeys" to prevent username enumeration
        conn |> put_status(:bad_request) |> json(%{error: "login not available"})

      user ->
        allow_credentials = Accounts.build_allowed_credentials(user.id)

        if allow_credentials == [] do
          conn
          |> put_status(:bad_request)
          |> json(%{error: "login not available"})
        else
          build_auth_challenge(conn, user, allow_credentials)
        end
    end
  end

  def login_challenge(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "username is required"})
  end

  defp build_auth_challenge(conn, user, allow_credentials) do
    wax_opts = webauthn_opts_for(conn, allow_credentials: allow_credentials)
    challenge = Wax.new_authentication_challenge(wax_opts)

    challenge_b64 = Base.url_encode64(challenge.bytes, padding: false)
    serialized = WebAuthnHelpers.serialize_challenge(challenge)

    allow_creds_json =
      Enum.map(allow_credentials, fn {cred_id, _} ->
        %{type: "public-key", id: Base.url_encode64(cred_id, padding: false)}
      end)

    conn
    |> put_session(:webauthn_challenge, serialized)
    |> put_session(:webauthn_user_id, user.id)
    |> json(%{
      challenge: challenge_b64,
      allowCredentials: allow_creds_json,
      timeout: 60_000,
      rpId: challenge.rp_id,
      userVerification: "preferred"
    })
  end

  @doc "POST /auth/login/complete — verify the authentication assertion"
  def login_complete(conn, params) do
    with {:ok, challenge} <- pop_challenge(conn),
         user_id when not is_nil(user_id) <- get_session(conn, :webauthn_user_id),
         {:ok, credential_id} <- decode_b64url(params["id"]),
         {:ok, auth_data_bin} <- decode_b64url(params["authenticatorData"]),
         {:ok, sig} <- decode_b64url(params["signature"]),
         {:ok, client_data_json} <- decode_b64url(params["clientDataJSON"]),
         {:ok, auth_data} <-
           Wax.authenticate(credential_id, auth_data_bin, sig, client_data_json, challenge) do
      passkey = Accounts.get_passkey_by_credential_id(credential_id)

      cloning_detected =
        passkey != nil and
          (passkey.sign_count > 0 or auth_data.sign_count > 0) and
          auth_data.sign_count <= passkey.sign_count

      if cloning_detected do
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "credential cloning detected"})
      else
        complete_auth(conn, passkey, auth_data, user_id)
      end
    else
      {:error, reason} ->
        Logger.error("WebAuthn authentication failed: #{inspect(reason)}")
        conn |> put_status(:unauthorized) |> json(%{error: "Authentication failed"})

      nil ->
        conn |> put_status(:bad_request) |> json(%{error: "session expired"})
    end
  end

  defp complete_auth(conn, passkey, auth_data, user_id) do
    if passkey, do: Accounts.update_sign_count(passkey, auth_data.sign_count)

    {:ok, session_token} = Accounts.create_user_session(user_id)

    conn
    |> configure_session(renew: true)
    |> delete_session(:webauthn_challenge)
    |> delete_session(:webauthn_user_id)
    |> put_session(:user_id, user_id)
    |> put_session(:session_token, session_token)
    |> json(%{ok: true})
  end

  # --- Logout ---

  def logout(conn, _params) do
    case get_session(conn, :session_token) do
      nil -> :ok
      token -> Accounts.delete_user_session(token)
    end

    conn
    |> clear_session()
    |> redirect(to: "/auth/login")
  end

  # --- Helpers ---

  defp pop_challenge(conn) do
    case get_session(conn, :webauthn_challenge) do
      nil ->
        {:error, :no_challenge}

      json_str when is_binary(json_str) ->
        {:ok, WebAuthnHelpers.deserialize_challenge(json_str)}
    end
  end

  defp decode_b64url(nil), do: {:error, :missing_field}
  defp decode_b64url(str), do: Base.url_decode64(str, padding: false)

  defp decode_b64url!(str), do: Base.url_decode64!(str, padding: false)

  # Builds Wax options for the current request. If the request Origin header
  # matches an allowed extra origin, overrides origin/rp_id for that call.
  # Falls back to the global wax_ config (eits.dev) for all other requests.
  defp webauthn_opts_for(conn, extra_opts \\ []) do
    base_opts = [trusted_attestation_types: [:none, :self]] ++ extra_opts
    request_origin = get_req_header(conn, "origin") |> List.first()
    extra_origins = Application.get_env(:eye_in_the_sky, :webauthn_extra_origins, [])

    if request_origin && request_origin in extra_origins do
      rp_id = URI.parse(request_origin).host
      [origin: request_origin, rp_id: rp_id] ++ base_opts
    else
      base_opts
    end
  end
end
