defmodule EyeInTheSky.Repo.Migrations.SessionsUtcTimestamps do
  use Ecto.Migration

  def up do
    # Convert existing timestamp columns to timestamptz (UTC-aware)
    execute "ALTER TABLE sessions ALTER COLUMN started_at TYPE timestamptz USING started_at::timestamp AT TIME ZONE 'UTC'"
    execute "ALTER TABLE sessions ALTER COLUMN last_activity_at TYPE timestamptz USING last_activity_at::timestamp AT TIME ZONE 'UTC'"
    execute "ALTER TABLE sessions ALTER COLUMN ended_at TYPE timestamptz USING ended_at::timestamp AT TIME ZONE 'UTC'"
    execute "ALTER TABLE sessions ALTER COLUMN archived_at TYPE timestamptz USING archived_at::timestamp AT TIME ZONE 'UTC'"

    # Add Ecto-managed timestamps (as timestamptz to match the schema)
    execute "ALTER TABLE sessions ADD COLUMN inserted_at timestamptz NOT NULL DEFAULT NOW()"
    execute "ALTER TABLE sessions ADD COLUMN updated_at timestamptz NOT NULL DEFAULT NOW()"

    # Backfill inserted_at from started_at where available
    execute "UPDATE sessions SET inserted_at = COALESCE(started_at, NOW()), updated_at = COALESCE(started_at, NOW())"
  end

  def down do
    alter table(:sessions) do
      remove :inserted_at
      remove :updated_at
    end

    execute "ALTER TABLE sessions ALTER COLUMN started_at TYPE timestamp WITHOUT TIME ZONE"
    execute "ALTER TABLE sessions ALTER COLUMN last_activity_at TYPE timestamp WITHOUT TIME ZONE"
    execute "ALTER TABLE sessions ALTER COLUMN ended_at TYPE timestamp WITHOUT TIME ZONE"
    execute "ALTER TABLE sessions ALTER COLUMN archived_at TYPE timestamp WITHOUT TIME ZONE"
  end
end
