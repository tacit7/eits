defmodule EyeInTheSky.Repo.Migrations.AddSourceSessionUuidToNotes do
  use Ecto.Migration

  def change do
    alter table(:notes) do
      add :source_session_uuid, :uuid
    end

    # Index to support filtering by source_session_uuid
    create index(:notes, [:source_session_uuid])
  end
end
