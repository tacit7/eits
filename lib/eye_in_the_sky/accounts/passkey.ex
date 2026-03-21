defmodule EyeInTheSky.Accounts.Passkey do
  use Ecto.Schema
  import Ecto.Changeset

  schema "passkeys" do
    field :credential_id, :binary
    field :cose_key, :binary
    field :sign_count, :integer, default: 0
    field :aaguid, :string
    field :friendly_name, :string

    belongs_to :user, EyeInTheSky.Accounts.User

    timestamps()
  end

  def changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:user_id, :credential_id, :cose_key, :sign_count, :aaguid, :friendly_name])
    |> validate_required([:user_id, :credential_id, :cose_key])
    |> unique_constraint(:credential_id)
  end
end
