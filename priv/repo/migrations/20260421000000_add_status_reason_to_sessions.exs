defmodule EyeInTheSky.Repo.Migrations.AddStatusReasonToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :status_reason, :string, null: true
    end
  end
end
