defmodule EyeInTheSky.Repo.Migrations.AddChannelMsgnumAndNotesParentIdIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create_if_not_exists index(:messages, [:channel_id, :channel_message_number],
                           name: :messages_channel_msgnum_idx,
                           concurrently: true,
                           where: "channel_message_number IS NOT NULL"
                         )

    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS notes_parent_id_bigint_project_idx
      ON notes ((parent_id::bigint))
      WHERE parent_type = 'project' AND parent_id ~ '^[0-9]+$'
    """
  end

  def down do
    drop_if_exists index(:messages, [:channel_id, :channel_message_number],
                     name: :messages_channel_msgnum_idx
                   )

    execute "DROP INDEX CONCURRENTLY IF EXISTS notes_parent_id_bigint_project_idx"
  end
end
