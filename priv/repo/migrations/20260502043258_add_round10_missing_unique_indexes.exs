defmodule EyeInTheSky.Repo.Migrations.AddRound10MissingUniqueIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @doc """
  Creates three unique indexes that exist in production but were never captured
  in migration files (migration drift). Without these indexes:

    - toggle_reaction/3        — on_conflict: conflict_target fails at runtime
    - upsert_session_context/1 — on_conflict: conflict_target fails at runtime
    - upsert_agent_context/1   — on_conflict: conflict_target fails at runtime

  All three use CREATE INDEX CONCURRENTLY via create_if_not_exists so this
  migration is safe to run on a live database and idempotent on re-runs.

  NOTE: the session_context.session_id index was previously created as a plain
  (non-unique) index. We drop it first inside a DO block so the unique variant
  can be added without a name collision.
  """
  def up do
    # message_reactions: unique (message_id, session_id, emoji) — required for
    # toggle_reaction/3 on_conflict: :nothing, conflict_target: [...]
    create_if_not_exists(
      unique_index(:message_reactions, [:message_id, :session_id, :emoji],
        name: :message_reactions_message_id_session_id_emoji_index,
        concurrently: true
      )
    )

    # session_context: unique (session_id) — the original migration created a
    # plain (non-unique) index; upsert_session_context/1 needs it UNIQUE for
    # on_conflict: conflict_target to succeed.
    # Drop the non-unique index first if it exists so we can replace it.
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'session_context'
          AND indexname = 'session_context_session_id_index'
          AND indexdef NOT LIKE '%UNIQUE%'
      ) THEN
        DROP INDEX CONCURRENTLY session_context_session_id_index;
      END IF;
    END
    $$;
    """)

    create_if_not_exists(
      unique_index(:session_context, [:session_id],
        name: :session_context_session_id_index,
        concurrently: true
      )
    )

    # agent_context: unique (agent_id, project_id) — the original migration
    # created a 3-column composite PK (agent_id, session_id, project_id) which
    # does not match the conflict_target: [:agent_id, :project_id] used by
    # upsert_agent_context/1.  The PK was later dropped manually; this adds the
    # correct unique index tracked in migrations.
    create_if_not_exists(
      unique_index(:agent_context, [:agent_id, :project_id],
        name: :agent_context_agent_id_project_id_index,
        concurrently: true
      )
    )
  end

  def down do
    drop_if_exists(
      unique_index(:message_reactions, [:message_id, :session_id, :emoji],
        name: :message_reactions_message_id_session_id_emoji_index
      )
    )

    drop_if_exists(
      unique_index(:session_context, [:session_id], name: :session_context_session_id_index)
    )

    drop_if_exists(
      unique_index(:agent_context, [:agent_id, :project_id],
        name: :agent_context_agent_id_project_id_index
      )
    )
  end
end
