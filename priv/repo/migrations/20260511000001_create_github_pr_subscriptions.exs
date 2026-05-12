defmodule EyeInTheSky.Repo.Migrations.CreateGithubPrSubscriptions do
  use Ecto.Migration

  def change do
    create table(:github_pr_subscriptions) do
      add :session_uuid, :uuid, null: false
      add :pr_number, :integer, null: false
      add :repository_full_name, :string, null: false
      add :active, :boolean, null: false, default: true

      timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime_usec)
    end

    create unique_index(:github_pr_subscriptions, [:session_uuid, :pr_number, :repository_full_name],
             name: :github_pr_subscriptions_session_pr_repo_unique
           )

    create index(:github_pr_subscriptions, [:pr_number, :repository_full_name])
    create index(:github_pr_subscriptions, [:session_uuid])
  end
end
