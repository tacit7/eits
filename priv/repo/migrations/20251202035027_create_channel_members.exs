defmodule EyeInTheSkyWeb.Repo.Migrations.CreateChannelMembers do
  use Ecto.Migration

  def change do
    create table(:channel_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_id, references(:channels, type: :string, on_delete: :delete_all), null: false
      add :agent_id, :string, null: false
      add :session_id, :string, null: false
      add :role, :string, default: "member", null: false
      add :joined_at, :utc_datetime, null: false
      add :last_read_at, :utc_datetime
      add :notifications, :string, default: "all", null: false

      timestamps(type: :utc_datetime)
    end

    create index(:channel_members, [:channel_id])
    create index(:channel_members, [:agent_id])
    create index(:channel_members, [:session_id])
    create unique_index(:channel_members, [:channel_id, :session_id])
  end
end
