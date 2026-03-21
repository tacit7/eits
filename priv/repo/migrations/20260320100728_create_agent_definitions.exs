defmodule EyeInTheSkyWeb.Repo.Migrations.CreateAgentDefinitions do
  use Ecto.Migration

  def change do
    create table(:agent_definitions) do
      add :slug, :string, null: false
      add :display_name, :string
      add :scope, :string, null: false
      add :project_id, references(:projects, on_delete: :delete_all)
      add :path, :text, null: false
      add :description, :text
      add :model, :string
      add :tools, {:array, :string}, default: []
      add :checksum, :string
      add :last_synced_at, :utc_datetime_usec
      add :missing_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # Check constraint: scope must be 'global' or 'project'
    create constraint(:agent_definitions, :scope_check, check: "scope IN ('global', 'project')")

    # Partial unique index: one slug per global scope
    create unique_index(:agent_definitions, [:slug], where: "scope = 'global'", name: :agent_definitions_global_slug)

    # Partial unique index: one slug per project
    create unique_index(:agent_definitions, [:project_id, :slug], where: "scope = 'project'", name: :agent_definitions_project_slug)

    create index(:agent_definitions, [:project_id])
    create index(:agent_definitions, [:scope])

    # Add FK from agents to agent_definitions
    alter table(:agents) do
      add :agent_definition_id, references(:agent_definitions, on_delete: :nilify_all)
      add :definition_checksum_at_spawn, :string
    end

    create index(:agents, [:agent_definition_id])
  end
end
