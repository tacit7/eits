defmodule EyeInTheSky.Repo.Migrations.AddSettingsToSessionsAndAgents do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :settings, :jsonb, default: fragment("'{}'::jsonb"), null: false
    end

    alter table(:agents) do
      add :settings, :jsonb, default: fragment("'{}'::jsonb"), null: false
    end
  end
end
