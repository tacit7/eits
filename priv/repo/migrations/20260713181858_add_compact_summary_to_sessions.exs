defmodule EyeInTheSky.Repo.Migrations.AddCompactSummaryToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :compact_summary, :text
    end
  end
end
