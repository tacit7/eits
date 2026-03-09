defmodule EyeInTheSkyWeb.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :uuid, :string, null: false
      add :title, :string, null: false
      add :body, :text
      add :category, :string, null: false, default: "system"
      add :read, :boolean, null: false, default: false
      add :resource_type, :string
      add :resource_id, :string

      timestamps()
    end

    create index(:notifications, [:read])
    create index(:notifications, [:inserted_at])
    create index(:notifications, [:category])
    create unique_index(:notifications, [:uuid])
  end
end
