defmodule EyeInTheSky.Repo.Migrations.AddMessagesBodyFtsIndex do
  use Ecto.Migration

  def change do
    execute(
      "CREATE INDEX messages_body_fts ON messages USING GIN (to_tsvector('english', COALESCE(body, '')))",
      "DROP INDEX messages_body_fts"
    )
  end
end
