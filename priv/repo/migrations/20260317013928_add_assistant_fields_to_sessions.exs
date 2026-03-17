defmodule EyeInTheSkyWeb.Repo.Migrations.AddAssistantFieldsToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :assistant_id, references(:assistants, on_delete: :nilify_all), null: true
      add :trigger_type, :string, null: true
      add :run_context, :map, null: true
    end

    create index(:sessions, [:assistant_id])
  end
end
