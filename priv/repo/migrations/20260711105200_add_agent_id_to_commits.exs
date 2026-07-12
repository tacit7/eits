defmodule EyeInTheSky.Repo.Migrations.AddAgentIdToCommits do
  use Ecto.Migration

  def change do
    alter table(:commits) do
      add :agent_id, references(:agents, on_delete: :nilify_all)
    end

    create index(:commits, [:agent_id])

    # Backfill agent_id from the linked session where session still exists.
    # Orphaned commits (session_id IS NULL) remain with agent_id NULL until
    # a new commit registration populates it.
    execute(
      """
      UPDATE commits c
      SET agent_id = s.agent_id
      FROM sessions s
      WHERE c.session_id = s.id
        AND c.agent_id IS NULL
      """,
      "UPDATE commits SET agent_id = NULL"
    )
  end
end
