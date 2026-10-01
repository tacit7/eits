defmodule EyeInTheSky.Repo.Migrations.AddManagedByAppToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :managed_by_app, :boolean, null: false, default: true
    end

    execute(
      "UPDATE sessions SET managed_by_app = false WHERE entrypoint = 'cli'",
      "UPDATE sessions SET managed_by_app = true WHERE entrypoint = 'cli'"
    )
  end
end
