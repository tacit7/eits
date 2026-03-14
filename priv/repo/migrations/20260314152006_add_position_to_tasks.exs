defmodule EyeInTheSkyWeb.Repo.Migrations.AddPositionToTasks do
  use Ecto.Migration

  def up do
    alter table(:tasks) do
      add :position, :integer, default: 0, null: false
    end

    # Seed initial positions based on created_at order within each state
    execute """
    UPDATE tasks t
    SET position = sub.row_num
    FROM (
      SELECT id, ROW_NUMBER() OVER (PARTITION BY state_id ORDER BY created_at ASC) AS row_num
      FROM tasks
    ) sub
    WHERE t.id = sub.id
    """

    create index(:tasks, [:state_id, :position])
  end

  def down do
    drop index(:tasks, [:state_id, :position])

    alter table(:tasks) do
      remove :position
    end
  end
end
