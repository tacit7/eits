defmodule EyeInTheSky.Repo.Migrations.AgentsUtcTimestamps do
  use Ecto.Migration

  def up do
    # Convert existing timestamp columns to timestamptz
    execute "ALTER TABLE agents ALTER COLUMN created_at TYPE timestamptz USING created_at::timestamp AT TIME ZONE 'UTC'"
    execute "ALTER TABLE agents ALTER COLUMN archived_at TYPE timestamptz USING archived_at::timestamp AT TIME ZONE 'UTC'"

    # Convert last_activity_at from text to timestamptz
    # Existing values are ISO8601 strings; cast via timestamptz handles this
    execute "ALTER TABLE agents ALTER COLUMN last_activity_at TYPE timestamptz USING last_activity_at::timestamptz"
  end

  def down do
    execute "ALTER TABLE agents ALTER COLUMN created_at TYPE timestamp WITHOUT TIME ZONE"
    execute "ALTER TABLE agents ALTER COLUMN archived_at TYPE timestamp WITHOUT TIME ZONE"
    execute "ALTER TABLE agents ALTER COLUMN last_activity_at TYPE text USING last_activity_at::text"
  end
end
