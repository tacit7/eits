defmodule EyeInTheSky.Repo.Migrations.AddRound9PerfIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # MEDIUM: notifications — composite (inserted_at DESC, id DESC) eliminates the
    # Incremental Sort that fires on every list_notifications call (12k+ rows).
    # The existing single-column inserted_at index forces a second sort pass for the
    # secondary id sort key.
    create_if_not_exists index(:notifications, [:inserted_at, :id],
                           name: :notifications_inserted_at_id_index,
                           concurrently: true
                         )

    # MEDIUM: messages — composite (session_id, inserted_at DESC) for session-scoped
    # time queries. Without this the planner incorrectly picks the
    # messages_channel_id_inserted_at_index for queries like find_recent_message and
    # recent_agent_bodies_for_session, scanning the full time window then filtering
    # on session_id. 275k+ rows on this table.
    create_if_not_exists index(:messages, [:session_id, :inserted_at],
                           name: :messages_session_id_inserted_at_index,
                           concurrently: true
                         )

    # MEDIUM: commit_tasks — missing standalone task_id index for ON DELETE CASCADE
    # reverse scan. The unique (commit_id, task_id) index covers commit-first lookups
    # but PG cannot efficiently use it as a plain task_id index. Without this,
    # deleting a task causes a full seqscan of commit_tasks.
    create_if_not_exists index(:commit_tasks, [:task_id],
                           name: :commit_tasks_task_id_index,
                           concurrently: true
                         )
  end

  def down do
    drop_if_exists index(:notifications, [], name: :notifications_inserted_at_id_index)

    drop_if_exists index(:messages, [], name: :messages_session_id_inserted_at_index)

    drop_if_exists index(:commit_tasks, [], name: :commit_tasks_task_id_index)
  end
end
