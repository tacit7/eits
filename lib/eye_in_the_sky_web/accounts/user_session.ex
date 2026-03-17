defmodule EyeInTheSkyWeb.Accounts.UserSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :id

  schema "user_sessions" do
    field :session_token, :string
    field :expires_at, :naive_datetime

    belongs_to :user, EyeInTheSkyWeb.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(user_session, attrs) do
    user_session
    |> cast(attrs, [:user_id, :session_token, :expires_at])
    |> validate_required([:user_id, :session_token, :expires_at])
    |> unique_constraint(:session_token)
  end
end
