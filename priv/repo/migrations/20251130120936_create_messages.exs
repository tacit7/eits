defmodule EyeInTheSkyWeb.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, references(:projects, type: :integer, on_delete: :delete_all)
      add :session_id, :string
      add :sender_role, :string, null: false
      add :recipient_role, :string
      add :provider, :string
      add :provider_session_id, :string
      add :direction, :string, null: false
      add :body, :text, null: false
      add :status, :string, default: "sent", null: false
      add :metadata, :string, default: "{}"

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:project_id])
    create index(:messages, [:session_id])
    create index(:messages, [:provider_session_id])
    create index(:messages, [:status])
    create index(:messages, [:inserted_at])
  end
end
