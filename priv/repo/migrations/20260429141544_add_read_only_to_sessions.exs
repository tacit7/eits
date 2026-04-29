defmodule EyeInTheSky.Repo.Migrations.AddReadOnlyToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :read_only, :boolean, default: false, null: false
    end
  end
end
