defmodule EyeInTheSky.Repo.Migrations.AddCanvasTerminals do
  use Ecto.Migration

  def change do
    create table(:canvas_terminals) do
      add :canvas_id, references(:canvases, on_delete: :delete_all), null: false
      add :pos_x, :integer, default: 0, null: false
      add :pos_y, :integer, default: 0, null: false
      add :width, :integer, default: 620, null: false
      add :height, :integer, default: 400, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:canvas_terminals, [:canvas_id])
  end
end
