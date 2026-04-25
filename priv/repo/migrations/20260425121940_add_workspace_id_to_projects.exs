defmodule EyeInTheSky.Repo.Migrations.AddWorkspaceIdToProjects do
  use Ecto.Migration

  def up do
    # Step 1: Seed one default workspace per existing user
    execute("""
    INSERT INTO workspaces (name, owner_user_id, "default", inserted_at, updated_at)
    SELECT 'Personal Workspace', id, true, NOW(), NOW()
    FROM users
    """)

    # Step 2: Add nullable workspace_id so we can backfill before enforcing not null
    alter table(:projects) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: true
    end

    # Step 3: Backfill all projects to the workspace of the lowest-id user (primary user)
    execute("""
    UPDATE projects
    SET workspace_id = (
      SELECT w.id FROM workspaces w
      ORDER BY w.owner_user_id ASC
      LIMIT 1
    )
    """)

    # Step 4: Enforce non-null now that all rows are filled
    alter table(:projects) do
      modify :workspace_id, :bigint, null: false
    end

    create index(:projects, [:workspace_id])

    # Unique project path per workspace — scoped so multi-workspace future works cleanly
    create unique_index(:projects, [:workspace_id, :path],
      where: "path IS NOT NULL",
      name: :projects_workspace_id_path_unique_index
    )
  end

  def down do
    drop_if_exists index(:projects, [:workspace_id, :path],
      name: :projects_workspace_id_path_unique_index
    )

    drop_if_exists index(:projects, [:workspace_id])

    alter table(:projects) do
      remove :workspace_id
    end
  end
end
