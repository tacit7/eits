defmodule EyeInTheSky.Repo.Migrations.AddMissingPerformanceIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create_if_not_exists index(:sessions, [:project_id], concurrently: true)

    create_if_not_exists index(:messages, [:parent_message_id],
                           where: "parent_message_id IS NOT NULL",
                           concurrently: true)

    create_if_not_exists index(:passkeys, [:user_id], concurrently: true)
    create_if_not_exists index(:sessions, [:last_activity_at], concurrently: true)
    create_if_not_exists index(:sessions, [:started_at], concurrently: true)

    create_if_not_exists index(:agents, [:status],
                           where: "status NOT IN ('completed', 'failed')",
                           name: :agents_pending_status_idx,
                           concurrently: true)
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
