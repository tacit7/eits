defmodule EyeInTheSky.Repo.Migrations.AddProjectIdToScheduledJobs do
  use Ecto.Migration

  def change do
    alter table(:scheduled_jobs) do
      add_if_not_exists :project_id, :bigint
    end
  end
end
