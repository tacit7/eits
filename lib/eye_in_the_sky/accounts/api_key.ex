defmodule EyeInTheSky.Accounts.ApiKey do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias EyeInTheSky.Repo

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "api_keys" do
    field :key_hash, :string
    field :label, :string
    field :valid_until, :naive_datetime

    timestamps(updated_at: false)
  end

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:key_hash, :label, :valid_until])
    |> validate_required([:key_hash, :label])
    |> unique_constraint(:key_hash)
  end

  @doc """
  Hash a raw token using HMAC-SHA256 with the app's secret_key_base.
  """
  def hash_token(token) do
    secret =
      Application.fetch_env!(:eye_in_the_sky, :secret_key_base)

    :crypto.mac(:hmac, :sha256, secret, token) |> Base.encode16(case: :lower)
  end

  @doc """
  Insert a new API key row. Returns {:ok, api_key} or {:error, changeset}.
  """
  def create(token, label, valid_until \\ nil) do
    %__MODULE__{}
    |> changeset(%{key_hash: hash_token(token), label: label, valid_until: valid_until})
    |> Repo.insert()
  end

  @doc """
  Check whether `token` matches any active API key in the database.
  An active key is one where valid_until is NULL or in the future.
  """
  def valid_db_token?(token) do
    hash = hash_token(token)
    now = NaiveDateTime.utc_now()

    query =
      from k in __MODULE__,
        where:
          k.key_hash == ^hash and
            (is_nil(k.valid_until) or k.valid_until > ^now)

    Repo.exists?(query)
  end
end
