defmodule EyeInTheSkyWeb.Repo.Migrations.AddParentFieldsToAgentsAndSessions do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :parent_agent_id, :bigint, null: true
      add :parent_session_id, :bigint, null: true
    end

    alter table(:sessions) do
      add :parent_agent_id, :bigint, null: true
      add :parent_session_id, :bigint, null: true
    end
  end
end
