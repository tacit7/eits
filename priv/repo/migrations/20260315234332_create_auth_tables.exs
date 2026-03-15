defmodule EyeInTheSkyWeb.Repo.Migrations.CreateAuthTables do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :text, null: false
      add :display_name, :text

      timestamps(type: :naive_datetime, default: fragment("now()"))
    end

    create unique_index(:users, [:username])

    create table(:passkeys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :cose_key, :binary, null: false
      add :sign_count, :bigint, null: false, default: 0
      add :aaguid, :text
      add :friendly_name, :text

      timestamps(type: :naive_datetime, default: fragment("now()"))
    end

    create unique_index(:passkeys, [:credential_id])

    create table(:registration_tokens) do
      add :token, :text, null: false
      add :username, :text, null: false
      add :expires_at, :naive_datetime, null: false

      timestamps(type: :naive_datetime, default: fragment("now()"))
    end

    create unique_index(:registration_tokens, [:token])
  end
end
