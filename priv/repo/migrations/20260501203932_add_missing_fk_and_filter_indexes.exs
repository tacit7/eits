defmodule EyeInTheSky.Repo.Migrations.AddMissingFkAndFilterIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # session_context.agent_id — FK column with no index.
    # Queries that filter by agent_id (e.g. fetching context for an agent) do a full scan
    # without this index.
    create_if_not_exists(
      index(:session_context, [:agent_id],
        concurrently: true,
        name: :session_context_agent_id_index
      )
    )

    # bookmarks.project_id — filter column used in list_bookmarks(project_id: ...).
    create_if_not_exists(
      index(:bookmarks, [:project_id],
        where: "project_id IS NOT NULL",
        concurrently: true,
        name: :bookmarks_project_id_index
      )
    )

    # bookmarks.agent_id — filter column used in list_bookmarks(agent_id: ...).
    create_if_not_exists(
      index(:bookmarks, [:agent_id],
        where: "agent_id IS NOT NULL",
        concurrently: true,
        name: :bookmarks_agent_id_index
      )
    )
  end
end
