defmodule EyeInTheSkyWeb.Repo.Migrations.CreateCanvases do
  use Ecto.Migration

  def change do
    create table(:canvases) do
      add :name, :text, null: false
      timestamps()
    end
  end
end
