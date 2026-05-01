defmodule EyeInTheSky.Repo.Migrations.AddParentFkIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # L1: parent_session_id on sessions — used for fork/checkpoint tree traversal.
    # Partial index (WHERE NOT NULL) skips the vast majority of non-fork sessions.
    create_if_not_exists(
      index(:sessions, [:parent_session_id],
        where: "parent_session_id IS NOT NULL",
        name: "sessions_parent_session_id_index",
        concurrently: true
      )
    )

    # L1: parent_agent_id on agents — mirrors the sessions FK pattern.
    create_if_not_exists(
      index(:agents, [:parent_agent_id],
        where: "parent_agent_id IS NOT NULL",
        name: "agents_parent_agent_id_index",
        concurrently: true
      )
    )
  end
end
