defmodule EyeInTheSkyWeb.Repo.Migrations.CreateMessageReactions do
  use Ecto.Migration

  def change do
    create table(:message_reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :message_id, references(:messages, type: :string, on_delete: :delete_all), null: false
      add :session_id, :string, null: false
      add :emoji, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:message_reactions, [:message_id])
    create unique_index(:message_reactions, [:message_id, :session_id, :emoji])
  end
end
