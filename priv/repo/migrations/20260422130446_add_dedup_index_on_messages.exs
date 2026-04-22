defmodule EyeInTheSky.Repo.Migrations.AddDedupIndexOnMessages do
  use Ecto.Migration

  def change do
    # Partial composite index to speed up find_unlinked_message lookups.
    # Used when deduplicating messages by body content for messages that don't
    # yet have a source_uuid (unlinked messages from manual chat history).
    #
    # Index covers: (session_id, sender_role, inserted_at) WHERE source_uuid IS NULL
    #
    # NOTE: `body` is intentionally NOT in the index. Long message bodies push
    # btree index rows past Postgres's 8191-byte page limit (error 54000:
    # program_limit_exceeded). The partial index on (session_id, sender_role,
    # inserted_at) with WHERE source_uuid IS NULL narrows to a small rowset,
    # so the body equality check is a cheap post-filter on the heap.
    create index(:messages,
      [:session_id, :sender_role, :inserted_at],
      where: "source_uuid IS NULL",
      name: "idx_messages_unlinked_dedup"
    )
  end
end
