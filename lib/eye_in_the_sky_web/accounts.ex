defmodule EyeInTheSkyWeb.Accounts do
  import Ecto.Query

  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Accounts.{User, Passkey, RegistrationToken, UserSession}

  # --- Users ---

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_username(username) do
    Repo.get_by(User, username: username)
  end

  def get_or_create_user(username) do
    case get_user_by_username(username) do
      nil ->
        %User{}
        |> User.changeset(%{username: username, display_name: username})
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  # --- Passkeys ---

  def list_passkeys_for_user(user_id) do
    Repo.all(from p in Passkey, where: p.user_id == ^user_id)
  end

  def get_passkey_by_credential_id(credential_id) do
    Repo.get_by(Passkey, credential_id: credential_id)
  end

  def create_passkey(attrs) do
    %Passkey{}
    |> Passkey.changeset(attrs)
    |> Repo.insert()
  end

  def update_sign_count(passkey, sign_count) do
    passkey
    |> Passkey.changeset(%{sign_count: sign_count})
    |> Repo.update()
  end

  # --- Registration tokens ---

  defp hash_registration_token(raw_token) do
    secret =
      Application.get_env(:eye_in_the_sky_web, EyeInTheSkyWebWeb.Endpoint)[:secret_key_base]

    :crypto.mac(:hmac, :sha256, secret, raw_token) |> Base.url_encode64(padding: false)
  end

  def create_registration_token(username, ttl_minutes \\ 15) do
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    hashed_token = hash_registration_token(raw_token)
    expires_at = NaiveDateTime.add(NaiveDateTime.utc_now(), ttl_minutes * 60, :second)

    result =
      %RegistrationToken{}
      |> RegistrationToken.changeset(%{
        token: hashed_token,
        username: username,
        expires_at: expires_at
      })
      |> Repo.insert()

    case result do
      {:ok, rt} -> {:ok, raw_token, rt}
      error -> error
    end
  end

  def peek_registration_token(raw_token) do
    hashed_token = hash_registration_token(raw_token)

    case Repo.get_by(RegistrationToken, token: hashed_token) do
      nil ->
        {:error, :not_found}

      rt ->
        if NaiveDateTime.compare(rt.expires_at, NaiveDateTime.utc_now()) == :gt,
          do: {:ok, rt.username},
          else: {:error, :expired}
    end
  end

  def consume_registration_token(raw_token) do
    hashed_token = hash_registration_token(raw_token)

    case Repo.get_by(RegistrationToken, token: hashed_token) do
      nil ->
        {:error, :not_found}

      rt ->
        if NaiveDateTime.compare(rt.expires_at, NaiveDateTime.utc_now()) == :gt do
          Repo.delete(rt)
          {:ok, rt.username}
        else
          Repo.delete(rt)
          {:error, :expired}
        end
    end
  end

  # --- User Sessions ---

  def create_user_session(user_id) do
    token = :crypto.strong_rand_bytes(32) |> Base.encode16()
    expires_at = NaiveDateTime.add(NaiveDateTime.utc_now(), 86_400 * 7, :second)

    result =
      %UserSession{}
      |> UserSession.changeset(%{user_id: user_id, session_token: token, expires_at: expires_at})
      |> Repo.insert()

    case result do
      {:ok, _} -> {:ok, token}
      error -> error
    end
  end

  def get_valid_user_session(token) when is_binary(token) do
    case Repo.get_by(UserSession, session_token: token) do
      nil ->
        nil

      session ->
        if NaiveDateTime.compare(session.expires_at, NaiveDateTime.utc_now()) == :gt,
          do: session,
          else: nil
    end
  end

  def delete_user_session(token) when is_binary(token) do
    case Repo.get_by(UserSession, session_token: token) do
      nil -> :ok
      session -> Repo.delete(session) && :ok
    end
  end

  # Builds the allow_credentials list that wax_ expects for authentication:
  # [{credential_id_binary, cose_key_term}]
  def build_allowed_credentials(user_id) do
    user_id
    |> list_passkeys_for_user()
    |> Enum.map(fn pk ->
      cose_key =
        pk.cose_key
        |> Jason.decode!()
        |> Map.new(fn {k, v} ->
          val = if is_map(v) and Map.has_key?(v, "b64"), do: Base.decode64!(v["b64"]), else: v
          {String.to_integer(k), val}
        end)

      {pk.credential_id, cose_key}
    end)
  end
end
