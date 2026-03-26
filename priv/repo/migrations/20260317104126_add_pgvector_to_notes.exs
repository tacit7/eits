defmodule EyeInTheSkyWeb.Repo.Migrations.AddPgvectorToNotes do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector")

    alter table(:notes) do
      add :embedding, :vector, size: 1536
      add :embedding_model, :string
    end

    execute(
      "CREATE INDEX notes_embedding_hnsw_idx ON notes USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS notes_embedding_hnsw_idx")

    alter table(:notes) do
      remove :embedding
      remove :embedding_model
    end
  end
end
