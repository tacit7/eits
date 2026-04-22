defmodule EyeInTheSky.Repo.Migrations.AddDedupIndexOnMessages do
  use Ecto.Migration

  def change do
    # Partial composite index to speed up find_unlinked_message body scan.
    # This index is used when deduplicating messages by body content for messages
    # that don't yet have a source_uuid (unlinked messages from manual chat history).
    #
    # Index covers: (session_id, sender_role, body, inserted_at)
    # Partial: WHERE source_uuid IS NULL
    #
    # This avoids a full-table scan when looking for unlinked messages by body
    # and session, especially for sessions with large message histories.
    create index(:messages,
      [:session_id, :sender_role, :body, :inserted_at],
      where: "source_uuid IS NULL",
      name: "idx_messages_unlinked_dedup"
    )
  end
end
