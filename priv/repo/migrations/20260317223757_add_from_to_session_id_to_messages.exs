defmodule EyeInTheSky.Repo.Migrations.AddFromToSessionIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :from_session_id, references(:sessions, on_delete: :nilify_all), null: true
      add :to_session_id, references(:sessions, on_delete: :nilify_all), null: true
    end

    create index(:messages, [:from_session_id])
    create index(:messages, [:to_session_id])
  end
end
