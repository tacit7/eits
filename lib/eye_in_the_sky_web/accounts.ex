defmodule EyeInTheSkyWeb.Accounts do
  import Ecto.Query

  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Accounts.{User, Passkey, RegistrationToken}

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

  def create_registration_token(username, ttl_minutes \\ 15) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    expires_at = NaiveDateTime.add(NaiveDateTime.utc_now(), ttl_minutes * 60, :second)

    %RegistrationToken{}
    |> RegistrationToken.changeset(%{token: token, username: username, expires_at: expires_at})
    |> Repo.insert()
  end

  def peek_registration_token(token) do
    case Repo.get_by(RegistrationToken, token: token) do
      nil ->
        {:error, :not_found}

      rt ->
        if NaiveDateTime.compare(rt.expires_at, NaiveDateTime.utc_now()) == :gt,
          do: {:ok, rt.username},
          else: {:error, :expired}
    end
  end

  def consume_registration_token(token) do
    case Repo.get_by(RegistrationToken, token: token) do
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

  # Builds the allow_credentials list that wax_ expects for authentication:
  # [{credential_id_binary, cose_key_term}]
  def build_allowed_credentials(user_id) do
    user_id
    |> list_passkeys_for_user()
    |> Enum.map(fn pk ->
      cose_key = :erlang.binary_to_term(pk.cose_key, [:safe])
      {pk.credential_id, cose_key}
    end)
  end
end
