defmodule EyeInTheSky.Repo.Migrations.AddIamDocumentIndexAndWinningSource do
  use Ecto.Migration

  def change do
    # Covers ON DELETE CASCADE and preload-by-document paths on iam_agent_type_documents.
    # The existing unique index on (agent_type, document_id) covers agent_type-first lookups
    # but not document_id-only scans (e.g. when cascading a document delete).
    create index(:iam_agent_type_documents, [:document_id],
             name: :iam_agent_type_documents_document_id
           )

    # Stores the EvaluationSource.label/1 string for the winning policy's source.
    # "global" or ~s(document "Name" → agent_type). Nil when decision is a fallback.
    alter table(:iam_decisions) do
      add :winning_source, :string
    end
  end
end
