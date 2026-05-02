defmodule EyeInTheSky.Repo.Migrations.AddTasksUpdatedAtAndSessionsActiveIndexes do
  use Ecto.Migration

  # Both indexes are created concurrently to avoid locking hot tables.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Turns Tasks.Poller's MAX(updated_at) from a seq scan into a 1-block backward index scan.
    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS tasks_updated_at_index ON tasks (updated_at DESC)"

    # The existing sessions_started_at_index has 0 scans because the dominant list_sessions
    # query includes WHERE archived_at IS NULL. This partial index matches that filter,
    # enabling index scans for the common case.
    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS sessions_active_started_at_idx ON sessions (started_at DESC) WHERE archived_at IS NULL"
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS sessions_active_started_at_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS tasks_updated_at_index"
  end
end
