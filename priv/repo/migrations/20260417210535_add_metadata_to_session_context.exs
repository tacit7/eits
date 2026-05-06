defmodule EyeInTheSky.Repo.Migrations.AddMetadataToSessionContext do
  use Ecto.Migration

  def change do
    alter table(:session_context) do
      add :metadata, :map, null: false, default: %{}
    end

    create index(:session_context, ["(metadata->>'source')"],
             name: :session_context_metadata_source_idx
           )
  end
end
