defmodule EyeInTheSkyWeb.Repo.Migrations.CreateFileAttachments do
  use Ecto.Migration

  def change do
    create table(:file_attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :message_id, references(:messages, type: :string, on_delete: :delete_all), null: false
      add :filename, :string, null: false
      add :original_filename, :string, null: false
      add :content_type, :string
      add :size_bytes, :bigint
      add :storage_path, :string, null: false
      add :upload_session_id, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:file_attachments, [:message_id])
  end
end
