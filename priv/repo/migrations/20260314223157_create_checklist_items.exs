defmodule EyeInTheSky.Repo.Migrations.CreateChecklistItems do
  use Ecto.Migration

  def change do
    create table(:checklist_items) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :completed, :boolean, default: false, null: false
      add :position, :integer, default: 0, null: false

      timestamps()
    end

    create index(:checklist_items, [:task_id])
    create index(:checklist_items, [:task_id, :position])
  end
end
