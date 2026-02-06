defmodule EyeInTheSkyWeb.Repo.Migrations.AddProjectIdToSessions do
  use Ecto.Migration

  def change do
    if table_exists?(:sessions) do
      alter table(:sessions) do
        add :project_id, :integer, null: true
      end

      # Backfill project_id from agent's project_id
      execute """
      UPDATE sessions
      SET project_id = (
        SELECT agents.project_id
        FROM agents
        WHERE agents.id = sessions.agent_id
        LIMIT 1
      )
      WHERE project_id IS NULL
      """

      # Add index for performance
      create index(:sessions, [:project_id])
    end
  end

  defp table_exists?(table) do
    case repo().query("SELECT name FROM sqlite_master WHERE type='table' AND name=?1", [
           Atom.to_string(table)
         ]) do
      {:ok, %{rows: rows}} -> length(rows) > 0
      {:error, _} -> false
    end
  end
end
