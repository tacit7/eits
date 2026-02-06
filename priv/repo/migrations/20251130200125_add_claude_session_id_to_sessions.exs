defmodule EyeInTheSkyWeb.Repo.Migrations.AddClaudeSessionIdToSessions do
  use Ecto.Migration

  def change do
    # Skip this migration if sessions table doesn't exist
    # (in fresh test databases, only sessions_v2 exists)
    if table_exists?(:sessions) do
      alter table(:sessions) do
        add :claude_session_id, :string
      end

      create index(:sessions, [:claude_session_id])
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
