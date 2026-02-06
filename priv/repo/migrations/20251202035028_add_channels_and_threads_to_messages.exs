defmodule EyeInTheSkyWeb.Repo.Migrations.AddChannelsAndThreadsToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :channel_id, references(:channels, type: :string, on_delete: :delete_all)
      add :parent_message_id, references(:messages, type: :string, on_delete: :delete_all)
      add :thread_reply_count, :integer, default: 0
      add :last_thread_reply_at, :utc_datetime
    end

    create index(:messages, [:channel_id])
    create index(:messages, [:parent_message_id])
    create index(:messages, [:channel_id, :inserted_at])
    create index(:messages, [:parent_message_id, :inserted_at])
  end
end
