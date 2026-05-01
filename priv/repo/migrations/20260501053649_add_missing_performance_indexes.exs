defmodule EyeInTheSky.Repo.Migrations.AddMissingPerformanceIndexes do
  use Ecto.Migration

  def up do
    create_if_not_exists index(:sessions, [:project_id])
    create_if_not_exists index(:messages, [:parent_message_id], where: "parent_message_id IS NOT NULL")
    create_if_not_exists index(:passkeys, [:user_id])
    create_if_not_exists index(:sessions, [:last_activity_at])
    create_if_not_exists index(:sessions, [:started_at])
    create_if_not_exists index(:agents, [:status], where: "status NOT IN ('completed', 'failed')", name: :agents_pending_status_idx)
  end

  def down do
    drop_if_exists index(:agents, [:status], name: :agents_pending_status_idx)
    drop_if_exists index(:sessions, [:started_at])
    drop_if_exists index(:sessions, [:last_activity_at])
    drop_if_exists index(:passkeys, [:user_id])
    drop_if_exists index(:messages, [:parent_message_id])
    drop_if_exists index(:sessions, [:project_id])
  end
end
