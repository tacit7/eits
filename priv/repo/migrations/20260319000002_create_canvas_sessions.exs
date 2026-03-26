defmodule EyeInTheSkyWeb.Repo.Migrations.CreateCanvasSessions do
  use Ecto.Migration

  def change do
    create table(:canvas_sessions) do
      add :canvas_id, references(:canvases, on_delete: :delete_all), null: false
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :pos_x, :integer, default: 0, null: false
      add :pos_y, :integer, default: 0, null: false
      add :width, :integer, default: 320, null: false
      add :height, :integer, default: 260, null: false
      timestamps()
    end

    create index(:canvas_sessions, [:canvas_id])
    create unique_index(:canvas_sessions, [:canvas_id, :session_id])
  end
end
