defmodule EyeInTheSkyWeb.Repo.Migrations.AddChannelMessageNumber do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :channel_message_number, :integer
    end

    create unique_index(:messages, [:channel_id, :channel_message_number],
             name: :messages_channel_id_message_number_index,
             where: "channel_id IS NOT NULL AND channel_message_number IS NOT NULL"
           )

    # Backfill existing channel messages with sequential numbers
    execute """
            WITH numbered AS (
              SELECT id, ROW_NUMBER() OVER (
                PARTITION BY channel_id
                ORDER BY inserted_at ASC, id ASC
              ) AS rn
              FROM messages
              WHERE channel_id IS NOT NULL
            )
            UPDATE messages SET channel_message_number = numbered.rn
            FROM numbered WHERE messages.id = numbered.id
            """,
            ""
  end
end
