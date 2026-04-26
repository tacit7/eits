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

    # Step 3: Backfill all projects to the workspace owned by the lowest-id user.
    # EITS is a single-user application — there is exactly one human user in the DB
    # (plus synthetic test-seed accounts). Assigning all projects to that user's
    # workspace is correct. If multi-user support is added in the future, this
    # migration will need a project-to-user join instead.
    execute("""
    UPDATE projects
    SET workspace_id = (
      SELECT w.id FROM workspaces w
      ORDER BY w.owner_user_id ASC
      LIMIT 1
    )
    """)

    # Step 4: Delete orphaned projects that have no workspace (test DBs with stale data)
    execute("DELETE FROM projects WHERE workspace_id IS NULL")

    # Step 5: Enforce non-null now that all rows are filled
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
