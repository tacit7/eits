defmodule EyeInTheSkyWebWeb.AuthController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.Accounts

  # --- Registration (token-gated) ---

  @doc "POST /auth/register/challenge — validate one-time token, return WebAuthn options"
  def register_challenge(conn, %{"token" => token}) when is_binary(token) and token != "" do
    case Accounts.peek_registration_token(token) do
      {:ok, username} ->
        challenge = Wax.new_registration_challenge(trusted_attestation_types: [:none, :self])

        rp_id = challenge.rp_id
        challenge_b64 = Base.url_encode64(challenge.bytes, padding: false)
        serialized = challenge |> :erlang.term_to_binary() |> Base.encode64()

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
        conn
        |> delete_session(:webauthn_challenge)
        |> delete_session(:webauthn_username)
        |> delete_session(:webauthn_reg_token)
        |> put_session(:user_id, user.id)
        |> json(%{ok: true})
      else
        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
      end
    else
      {:error, :expired} ->
        conn |> put_status(:gone) |> json(%{error: "registration link has expired"})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})

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
        conn |> put_status(:not_found) |> json(%{error: "user not found"})

      user ->
        allow_credentials = Accounts.build_allowed_credentials(user.id)

        if allow_credentials == [] do
          conn
          |> put_status(:bad_request)
          |> json(%{error: "no passkeys registered for this user"})
        else
          challenge = Wax.new_authentication_challenge(allow_credentials: allow_credentials)

          challenge_b64 = Base.url_encode64(challenge.bytes, padding: false)
          serialized = challenge |> :erlang.term_to_binary() |> Base.encode64()

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
    end
  end

  def login_challenge(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "username is required"})
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
      if passkey, do: Accounts.update_sign_count(passkey, auth_data.sign_count)

      conn
      |> delete_session(:webauthn_challenge)
      |> delete_session(:webauthn_user_id)
      |> put_session(:user_id, user_id)
      |> json(%{ok: true})
    else
      {:error, reason} ->
        conn |> put_status(:unauthorized) |> json(%{error: inspect(reason)})

      nil ->
        conn |> put_status(:bad_request) |> json(%{error: "session expired"})
    end
  end

  # --- Logout ---

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/auth/login")
  end

  # --- Helpers ---

  defp pop_challenge(conn) do
    case get_session(conn, :webauthn_challenge) do
      nil ->
        {:error, :no_challenge}

      encoded ->
        challenge = encoded |> Base.decode64!() |> :erlang.binary_to_term([:safe])
        {:ok, challenge}
    end
  end

  defp decode_b64url(nil), do: {:error, :missing_field}
  defp decode_b64url(str), do: Base.url_decode64(str, padding: false)

  defp decode_b64url!(str), do: Base.url_decode64!(str, padding: false)
end
