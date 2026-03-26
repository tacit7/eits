defmodule EyeInTheSkyWeb.Repo.Migrations.CreateToolApprovals do
  use Ecto.Migration

  def change do
    create table(:tool_approvals) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :assistant_id, references(:assistants, on_delete: :nilify_all)
      add :tool_name, :string, null: false
      add :payload, :map, default: %{}
      add :status, :string, default: "pending", null: false
      add :requested_by_type, :string
      add :requested_by_id, :string
      add :reviewed_by_id, :integer
      add :reviewed_at, :naive_datetime
      add :expires_at, :naive_datetime
      add :inserted_at, :naive_datetime
      add :updated_at, :naive_datetime
    end

    create index(:tool_approvals, [:session_id])
    create index(:tool_approvals, [:assistant_id])
    create index(:tool_approvals, [:status])
    create index(:tool_approvals, [:tool_name])
  end
end
