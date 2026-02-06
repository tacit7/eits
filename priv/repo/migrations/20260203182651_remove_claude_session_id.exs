defmodule EyeInTheSkyWeb.Repo.Migrations.RemoveClaudeSessionId do
  use Ecto.Migration

  def change do
    if table_exists?(:sessions) do
      alter table(:sessions) do
        remove :claude_session_id, :string
      end
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
