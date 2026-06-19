defmodule EyeInTheSky.PullRequests.PullRequest do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pull_requests" do
    field :session_id, :integer
    field :pr_number, :integer
    field :pr_url, :string
    field :base_branch, :string
    field :head_branch, :string
    # GitHub sync fields
    field :github_pr_id, :integer
    field :repository_full_name, :string
    field :repository_id, :integer
    field :title, :string
    field :state, :string
    field :draft, :boolean
    field :merged, :boolean
    field :author_login, :string
    field :last_synced_at, :utc_datetime_usec

    belongs_to :session, EyeInTheSky.Sessions.Session,
      define_field: false,
      foreign_key: :session_id,
      type: :integer

    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime)
  end

  @doc "Changeset for the existing app-level PR creation (session-owned)."
  def changeset(pr, attrs) do
    pr
    |> cast(attrs, [
      :session_id,
      :pr_number,
      :pr_url,
      :base_branch,
      :head_branch,
      :github_pr_id,
      :repository_full_name,
      :repository_id,
      :title,
      :state,
      :draft,
      :merged,
      :author_login,
      :last_synced_at
    ])
    |> validate_required([:session_id])
    |> validate_number(:pr_number, greater_than: 0)
    |> validate_format(:pr_url, ~r/^https?:/, message: "must be a valid URL")
    |> unique_constraint(:github_pr_id, name: :pull_requests_github_pr_id_index)
  end

  @doc "Changeset for upserts driven by GitHub webhook sync."
  def github_sync_changeset(pr, attrs) do
    pr
    |> cast(attrs, [
      :github_pr_id,
      :repository_full_name,
      :repository_id,
      :pr_number,
      :title,
      :state,
      :draft,
      :merged,
      :author_login,
      :head_branch,
      :base_branch,
      :last_synced_at
    ])
    |> validate_required([:github_pr_id, :repository_full_name])
    |> validate_number(:pr_number, greater_than: 0)
    |> unique_constraint(:github_pr_id, name: :pull_requests_github_pr_id_index)
  end
end
