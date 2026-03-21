defmodule EyeInTheSky.Repo.Migrations.CreateUserSessions do
  use Ecto.Migration

  def change do
    create table(:user_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :session_token, :string, null: false
      add :expires_at, :naive_datetime, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:user_sessions, [:session_token])
    create index(:user_sessions, [:user_id])
  end
end
