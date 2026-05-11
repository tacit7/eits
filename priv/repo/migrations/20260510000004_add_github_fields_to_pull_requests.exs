defmodule EyeInTheSky.Repo.Migrations.AddGithubFieldsToPullRequests do
  use Ecto.Migration

  def change do
    alter table(:pull_requests) do
      add :github_pr_id, :bigint
      add :repository_full_name, :string
      add :repository_id, :bigint
      add :title, :string
      add :state, :string
      add :draft, :boolean
      add :merged, :boolean
      add :author_login, :string
      add :last_synced_at, :utc_datetime_usec
    end

    create index(:pull_requests, [:github_pr_id],
             unique: true,
             where: "github_pr_id IS NOT NULL",
             name: :pull_requests_github_pr_id_index
           )
  end
end
