defmodule EyeInTheSkyWeb.Repo.Migrations.ChangeAgentLastActivityAtToText do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE agents
    ALTER COLUMN last_activity_at TYPE text
    USING to_char(last_activity_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    """
  end

  def down do
    execute """
    ALTER TABLE agents
    ALTER COLUMN last_activity_at TYPE timestamp without time zone
    USING last_activity_at::timestamp without time zone
    """
  end
end
