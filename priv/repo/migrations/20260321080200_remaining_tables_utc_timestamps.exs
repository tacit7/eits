defmodule EyeInTheSky.Repo.Migrations.RemainingTablesUtcTimestamps do
  use Ecto.Migration

  def up do
    # tasks
    for col <- ~w(created_at updated_at completed_at due_at) do
      execute "ALTER TABLE tasks ALTER COLUMN #{col} TYPE timestamptz USING #{col} AT TIME ZONE 'UTC'"
    end

    # notes
    execute "ALTER TABLE notes ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC'"

    # session_context
    for col <- ~w(created_at updated_at) do
      execute "ALTER TABLE session_context ALTER COLUMN #{col} TYPE timestamptz USING #{col} AT TIME ZONE 'UTC'"
    end

    # session_logs
    execute "ALTER TABLE session_logs ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC'"

    # scheduled_jobs
    for col <- ~w(created_at updated_at last_run_at next_run_at) do
      execute "ALTER TABLE scheduled_jobs ALTER COLUMN #{col} TYPE timestamptz USING #{col} AT TIME ZONE 'UTC'"
    end

    # job_runs
    for col <- ~w(started_at completed_at created_at) do
      execute "ALTER TABLE job_runs ALTER COLUMN #{col} TYPE timestamptz USING #{col} AT TIME ZONE 'UTC'"
    end
  end

  def down do
    for col <- ~w(created_at updated_at completed_at due_at) do
      execute "ALTER TABLE tasks ALTER COLUMN #{col} TYPE timestamp WITHOUT TIME ZONE"
    end

    execute "ALTER TABLE notes ALTER COLUMN created_at TYPE timestamp WITHOUT TIME ZONE"

    for col <- ~w(created_at updated_at) do
      execute "ALTER TABLE session_context ALTER COLUMN #{col} TYPE timestamp WITHOUT TIME ZONE"
    end

    execute "ALTER TABLE session_logs ALTER COLUMN created_at TYPE timestamp WITHOUT TIME ZONE"

    for col <- ~w(created_at updated_at last_run_at next_run_at) do
      execute "ALTER TABLE scheduled_jobs ALTER COLUMN #{col} TYPE timestamp WITHOUT TIME ZONE"
    end

    for col <- ~w(started_at completed_at created_at) do
      execute "ALTER TABLE job_runs ALTER COLUMN #{col} TYPE timestamp WITHOUT TIME ZONE"
    end
  end
end
