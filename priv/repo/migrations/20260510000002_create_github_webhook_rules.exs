defmodule EyeInTheSky.Repo.Migrations.CreateGithubWebhookRules do
  use Ecto.Migration

  def change do
    create table(:github_webhook_rules) do
      add :event_type, :string, null: false
      add :repository_full_name, :string
      add :project_id, :bigint
      add :branch_glob, :string
      add :target_branch_glob, :string
      add :action_type, :string, null: false
      add :action_config, :map, null: false, default: %{}
      add :guard_config, :map, null: false, default: %{}
      add :enabled, :boolean, null: false, default: true
      add :priority, :integer, null: false, default: 100

      timestamps(type: :utc_datetime_usec)
    end

    create index(:github_webhook_rules, [:enabled, :event_type, :repository_full_name])
  end
end
