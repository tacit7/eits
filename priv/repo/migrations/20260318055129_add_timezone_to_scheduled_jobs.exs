defmodule EyeInTheSkyWeb.Repo.Migrations.AddTimezoneToScheduledJobs do
  use Ecto.Migration

  def change do
    alter table(:scheduled_jobs) do
      add :timezone, :string, default: "Etc/UTC"
    end
  end
end
