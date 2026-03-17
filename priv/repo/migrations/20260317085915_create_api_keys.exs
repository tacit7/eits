defmodule EyeInTheSkyWeb.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :key_hash, :string, null: false
      add :label, :string, null: false
      add :valid_until, :naive_datetime, null: true

      timestamps(updated_at: false)
    end

    create unique_index(:api_keys, [:key_hash])
  end
end
