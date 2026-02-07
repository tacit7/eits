defmodule EyeInTheSkyWeb.Repo.Migrations.AddProjectIdToSessions do
  use Ecto.Migration

  def change do
    if table_exists?(:sessions) && !column_exists?(:sessions, :project_id) do
      alter table(:sessions) do
        add :project_id, :integer, null: true
      end

      # Skip backfill - agents table doesn't have project_id column in MCP server schema
      # The MCP server uses project_name (TEXT) instead

      # Add index for performance
      create index(:sessions, [:project_id])
    end
  end

  defp column_exists?(table, column) do
    case repo().query("PRAGMA table_info(#{table})", []) do
      {:ok, %{rows: rows}} ->
        Enum.any?(rows, fn row ->
          # SQLite PRAGMA table_info returns: [cid, name, type, notnull, dflt_value, pk]
          Enum.at(row, 1) == Atom.to_string(column)
        end)

      {:error, _} ->
        false
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
