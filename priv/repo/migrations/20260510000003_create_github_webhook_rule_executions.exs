defmodule EyeInTheSky.Repo.Migrations.CreateGithubWebhookRuleExecutions do
  use Ecto.Migration

  def change do
    create table(:github_webhook_rule_executions) do
      add :rule_id, :bigint, null: false
      add :delivery_id, :string, null: false
      add :repository_full_name, :string
      add :pr_number, :integer
      add :status, :string, null: false
      add :result, :map
      add :error_message, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:github_webhook_rule_executions,
             [:rule_id, :repository_full_name, :pr_number, :status]
           )
  end
end
