defmodule EyeInTheSky.Github.PrSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "github_pr_subscriptions" do
    field :session_uuid, Ecto.UUID
    field :pr_number, :integer
    field :repository_full_name, :string
    field :active, :boolean, default: true

    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:session_uuid, :pr_number, :repository_full_name, :active])
    |> validate_required([:session_uuid, :pr_number, :repository_full_name])
    |> validate_number(:pr_number, greater_than: 0)
    |> unique_constraint([:session_uuid, :pr_number, :repository_full_name],
         name: :github_pr_subscriptions_session_pr_repo_unique
       )
  end
end
