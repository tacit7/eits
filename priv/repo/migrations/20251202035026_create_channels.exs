defmodule EyeInTheSkyWeb.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :channel_type, :string, default: "public", null: false
      add :project_id, references(:projects, type: :integer, on_delete: :delete_all)
      add :created_by_session_id, :string
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:channels, [:project_id])
    create index(:channels, [:channel_type])
    create index(:channels, [:archived_at])
    create unique_index(:channels, [:project_id, :name], where: "archived_at IS NULL")
  end
end
