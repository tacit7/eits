defmodule EyeInTheSky.Repo.Migrations.AddMessagesBodyFtsIndex do
  use Ecto.Migration

  # CONCURRENTLY cannot run inside a transaction
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS messages_body_fts ON messages USING GIN (to_tsvector('english', COALESCE(body, '')))",
      "DROP INDEX CONCURRENTLY IF EXISTS messages_body_fts"
    )
  end
end
