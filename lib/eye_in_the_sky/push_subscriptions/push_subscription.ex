defmodule EyeInTheSky.PushSubscriptions.PushSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "push_subscriptions" do
    field :endpoint, :string
    field :auth, :string
    field :p256dh, :string

    timestamps()
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:endpoint, :auth, :p256dh])
    |> validate_required([:endpoint, :auth, :p256dh])
    |> unique_constraint(:endpoint)
  end
end
