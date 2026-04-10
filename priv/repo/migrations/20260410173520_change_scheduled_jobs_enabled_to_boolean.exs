defmodule EyeInTheSky.Repo.Migrations.ChangeScheduledJobsEnabledToBoolean do
  use Ecto.Migration

  def change do
    execute "ALTER TABLE scheduled_jobs ALTER COLUMN enabled DROP DEFAULT"
    execute "ALTER TABLE scheduled_jobs ALTER COLUMN enabled TYPE boolean USING (enabled::boolean)"
    execute "ALTER TABLE scheduled_jobs ALTER COLUMN enabled SET DEFAULT true"
  end
end
