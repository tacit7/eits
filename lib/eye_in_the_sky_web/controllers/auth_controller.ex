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
    # Bug 2 fix: consume challenge immediately so it cannot be replayed even on failure
    {conn, challenge_result} = pop_challenge(conn)

    with {:ok, challenge} <- challenge_result,
         username when not is_nil(username) <- get_session(conn, :webauthn_username),
         token when not is_nil(token) <- get_session(conn, :webauthn_reg_token),
         {:ok, ^username} <- Accounts.consume_registration_token(token),
         {:ok, attestation_object} <- decode_b64url(params["attestationObject"]),
         {:ok, client_data_json} <- decode_b64url(params["clientDataJSON"]),
         # Bug 1 fix: use non-raising decode_b64url/1 instead of decode_b64url!/1
         {:ok, credential_id_raw} <- decode_b64url(params["id"]),
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
        # Bug 4 fix: handle session creation failure instead of hard-crashing on match
        case Accounts.create_user_session(user.id) do
          {:ok, session_token} ->
            conn
            |> configure_session(renew: true)
            |> delete_session(:webauthn_challenge)
            |> delete_session(:webauthn_username)
            |> delete_session(:webauthn_reg_token)
            |> put_session(:user_id, user.id)
            |> put_session(:session_token, session_token)
            |> json(%{ok: true})

          {:error, reason} ->
            Logger.error("Failed to create user session during registration: #{inspect(reason)}")

            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to create session"})
        end
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
      {:error, :not_found} ->
        # Return same error as "no passkeys" to prevent username enumeration
        conn |> put_status(:bad_request) |> json(%{error: "login not available"})

      {:ok, user} ->
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
    # Bug 2 fix: consume challenge immediately so it cannot be replayed even on failure
    {conn, challenge_result} = pop_challenge(conn)

    with {:ok, challenge} <- challenge_result,
         user_id when not is_nil(user_id) <- get_session(conn, :webauthn_user_id),
         {:ok, credential_id} <- decode_b64url(params["id"]),
         {:ok, auth_data_bin} <- decode_b64url(params["authenticatorData"]),
         {:ok, sig} <- decode_b64url(params["signature"]),
         {:ok, client_data_json} <- decode_b64url(params["clientDataJSON"]),
         {:ok, auth_data} <-
           Wax.authenticate(credential_id, auth_data_bin, sig, client_data_json, challenge) do
      passkey_result = Accounts.get_passkey_by_credential_id(credential_id)

      cloning_detected =
        match?({:ok, _}, passkey_result) and
          (elem(passkey_result, 1).sign_count > 0 or auth_data.sign_count > 0) and
          auth_data.sign_count <= elem(passkey_result, 1).sign_count

      if cloning_detected do
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "credential cloning detected"})
      else
        passkey =
          case passkey_result do
            {:ok, pk} -> pk
            {:error, :not_found} -> nil
          end

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
    # Bug 3 fix: log sign_count update failures instead of silently ignoring them
    if passkey do
      case Accounts.update_sign_count(passkey, auth_data.sign_count) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Failed to update sign_count for passkey #{passkey.id}: #{inspect(reason)}"
          )
      end
    end

    # Bug 4 fix: handle session creation failure instead of hard-crashing on match
    case Accounts.create_user_session(user_id) do
      {:ok, session_token} ->
        conn
        |> configure_session(renew: true)
        |> delete_session(:webauthn_challenge)
        |> delete_session(:webauthn_user_id)
        |> put_session(:user_id, user_id)
        |> put_session(:session_token, session_token)
        |> json(%{ok: true})

      {:error, reason} ->
        Logger.error("Failed to create user session during authentication: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to create session"})
    end
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

  # Bug 2 fix: deletes the challenge from the session on every read so it
  # cannot be replayed. Returns {updated_conn, {:ok, challenge} | {:error, reason}}.
  defp pop_challenge(conn) do
    case get_session(conn, :webauthn_challenge) do
      nil ->
        {conn, {:error, :no_challenge}}

      json_str when is_binary(json_str) ->
        conn = delete_session(conn, :webauthn_challenge)
        {conn, {:ok, WebAuthnHelpers.deserialize_challenge(json_str)}}
    end
  end

  defp decode_b64url(nil), do: {:error, :missing_field}

  defp decode_b64url(str) do
    case Base.url_decode64(str, padding: false) do
      {:ok, binary} -> {:ok, binary}
      # Base.url_decode64 returns bare :error on invalid input; normalize it so
      # callers always see {:ok, _} | {:error, _} and the with-chain else
      # clause can match it uniformly.
      :error -> {:error, :invalid_encoding}
    end
  end

  # Builds Wax options for the current request. If the request Origin header
  # matches an allowed extra origin, overrides origin/rp_id for that call.
  # Falls back to the global wax_ config (eits.dev) for all other requests.
  defp webauthn_opts_for(conn, extra_opts \\ []) do
    base_opts = [trusted_attestation_types: [:none, :self]] ++ extra_opts
    request_origin = get_req_header(conn, "origin") |> List.first()
    extra_origins = Application.get_env(:eye_in_the_sky, :webauthn_extra_origins, [])

    if not is_nil(request_origin) && request_origin in extra_origins do
      rp_id = URI.parse(request_origin).host
      [origin: request_origin, rp_id: rp_id] ++ base_opts
    else
      base_opts
    end
  end
end
