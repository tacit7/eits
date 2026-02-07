defmodule EyeInTheSkyWeb.Repo.Migrations.RemoveClaudeSessionId do
  use Ecto.Migration

  def change do
    if table_exists?(:sessions) && column_exists?(:sessions, :claude_session_id) do
      # Drop the index first to avoid SQLite errors during column drop
      drop_if_exists index(:sessions, [:claude_session_id])

      alter table(:sessions) do
        remove :claude_session_id, :string
      end
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
