defmodule EyeInTheSkyWeb.PullRequests.PullRequest do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pull_requests" do
    field :session_id, :integer
    field :pr_number, :integer
    field :pr_url, :string
    field :base_branch, :string
    field :head_branch, :string

    belongs_to :session, EyeInTheSkyWeb.Sessions.Session,
      define_field: false,
      foreign_key: :session_id,
      type: :integer

    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime)
  end

  @doc false
  def changeset(pr, attrs) do
    pr
    |> cast(attrs, [:session_id, :pr_number, :pr_url, :base_branch, :head_branch])
    |> validate_required([:session_id])
    |> validate_number(:pr_number, greater_than: 0)
    |> validate_format(:pr_url, ~r/^https?:/, message: "must be a valid URL")
  end
end
