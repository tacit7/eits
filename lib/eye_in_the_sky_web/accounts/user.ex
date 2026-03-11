defmodule EyeInTheSkyWeb.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :display_name, :string

    has_many :passkeys, EyeInTheSkyWeb.Accounts.Passkey

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :display_name])
    |> validate_required([:username])
    |> validate_length(:username, min: 1, max: 64)
    |> unique_constraint(:username)
  end
end
