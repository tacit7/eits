defmodule EyeInTheSkyWeb.Repo.Migrations.AddSearchIndexes do
  use Ecto.Migration

  def change do
    if table_exists?(:sessions) do
      # Indexes for session search by name
      create index(:sessions, [:name])

      # Combined index for efficient session + agent filtering
      create index(:sessions, [:agent_id, :ended_at])
    end

    if table_exists?(:agents) do
      # Indexes for agent search by description and project
      create index(:agents, [:description])
      create index(:agents, [:project_name])
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
