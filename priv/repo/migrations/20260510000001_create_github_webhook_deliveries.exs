defmodule EyeInTheSky.Repo.Migrations.CreateGithubWebhookDeliveries do
  use Ecto.Migration

  def change do
    create table(:github_webhook_deliveries) do
      add :delivery_id, :string, null: false
      add :hook_id, :string
      add :event_type, :string, null: false
      add :event_header, :string, null: false
      add :action, :string
      add :repository_full_name, :string
      add :sender_login, :string
      add :pr_number, :integer
      add :head_branch, :string
      add :base_branch, :string
      add :payload, :map
      add :status, :string, null: false, default: "pending"
      add :error_message, :string
      add :processing_started_at, :utc_datetime_usec
      add :processed_at, :utc_datetime_usec
      add :attempt_count, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 5
      add :duplicate_count, :integer, null: false, default: 0
      add :last_duplicate_at, :utc_datetime_usec
      add :received_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_webhook_deliveries, [:delivery_id])
    create index(:github_webhook_deliveries, [:status, :received_at])

    create index(:github_webhook_deliveries, [:processing_started_at],
             where: "status = 'processing'",
             name: :github_webhook_deliveries_stale_processing_index
           )
  end
end
