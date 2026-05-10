defmodule EyeInTheSky.Repo.Migrations.CreateSessionCheckpoints do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:session_checkpoints) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :name, :string
      add :description, :string
      add :message_index, :integer, default: 0, null: false
      add :git_stash_ref, :string
      add :metadata, :map, default: %{}
      add :inserted_at, :utc_datetime
    end

    create_if_not_exists index(:session_checkpoints, [:session_id])
  end
end
