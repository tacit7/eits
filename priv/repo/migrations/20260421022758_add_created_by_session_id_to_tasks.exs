defmodule EyeInTheSky.Repo.Migrations.AddCreatedBySessionIdToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :created_by_session_id, references(:sessions, on_delete: :nilify_all)
    end

    create index(:tasks, [:created_by_session_id])
  end
end
