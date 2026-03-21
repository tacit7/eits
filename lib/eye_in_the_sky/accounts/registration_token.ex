defmodule EyeInTheSky.Accounts.RegistrationToken do
  use Ecto.Schema
  import Ecto.Changeset

  schema "registration_tokens" do
    field :token, :string
    field :username, :string
    field :expires_at, :naive_datetime

    timestamps(updated_at: false)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:token, :username, :expires_at])
    |> validate_required([:token, :username, :expires_at])
    |> unique_constraint(:token)
  end
end
