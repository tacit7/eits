defmodule EyeInTheSky.Repo.Migrations.MigrateUuidColumnsToNativeUuid do
  use Ecto.Migration

  @doc """
  Converts all uuid columns from varchar to native PostgreSQL uuid type.

  The original migrations created these as :string (varchar), but the dev DB
  was manually altered to native uuid. This migration aligns the test DB and
  any fresh installs with the schema expectation of Ecto.UUID fields.

  """

  def up do
    for table <- ~w(agents sessions tasks messages notes channels channel_members
                     teams message_reactions file_attachments notifications
                     bookmarks subagent_prompts)a do
      execute """
      ALTER TABLE #{table}
        ALTER COLUMN uuid TYPE uuid USING uuid::uuid
      """
    end

    # messages.source_uuid also needs to be native uuid
    execute "ALTER TABLE messages ALTER COLUMN source_uuid TYPE uuid USING source_uuid::uuid"
  end

  def down do
    for table <- ~w(agents sessions tasks messages notes channels channel_members
                     teams message_reactions file_attachments notifications
                     bookmarks subagent_prompts)a do
      execute """
      ALTER TABLE #{table}
        ALTER COLUMN uuid TYPE varchar(255) USING uuid::text
      """
    end

    execute "ALTER TABLE messages ALTER COLUMN source_uuid TYPE varchar(255) USING source_uuid::text"
  end
end
