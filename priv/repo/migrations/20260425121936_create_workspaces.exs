defmodule EyeInTheSky.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    create table(:workspaces) do
      add :name, :string, null: false
      add :owner_user_id, references(:users, on_delete: :delete_all), null: false
      add :default, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:workspaces, [:owner_user_id])

    # Only one default workspace per user
    create unique_index(:workspaces, [:owner_user_id],
             where: "\"default\" = true",
             name: :workspaces_owner_user_id_default_unique_index
           )
  end
end
