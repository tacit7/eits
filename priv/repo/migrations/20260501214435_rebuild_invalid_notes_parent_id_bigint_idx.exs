defmodule EyeInTheSky.Repo.Migrations.RebuildInvalidNotesParentIdBigintIdx do
  use Ecto.Migration

  # notes_parent_id_bigint_project_idx was left in an INVALID state
  # (indisvalid=false, indisready=false) from a prior CREATE INDEX CONCURRENTLY
  # run. An INVALID index is never consulted by the query planner but still
  # imposes write overhead on every INSERT/UPDATE/DELETE to notes. Drop it
  # and recreate it cleanly.
  #
  # The WHERE clause keeps parent_id ~ '^[0-9]+$' so non-numeric legacy
  # strings (UUIDs, slugs) do not cause a cast error.

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute "DROP INDEX CONCURRENTLY IF EXISTS notes_parent_id_bigint_project_idx"

    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS notes_parent_id_bigint_project_idx
      ON notes ((parent_id::bigint))
      WHERE parent_type = 'project' AND parent_id ~ '^[0-9]+$'
    """
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS notes_parent_id_bigint_project_idx"
  end
end
