defmodule EyeInTheSky.Repo.Migrations.AddScheduledJobsPerfIndexes do
  use Ecto.Migration

  # M-3: Partial index on next_run_at for due_jobs/0 poll — avoids full table scan every tick.
  # M-5: Functional index on config::jsonb->>'agent_file_id' for fs_agent_already_scheduled?/1
  #       — avoids per-row text→jsonb cast with no index.
  # L-3: Index on project_id FK used in list_jobs/1 project filter.

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # M-3: due_jobs poll: WHERE enabled = true AND next_run_at IS NOT NULL AND next_run_at <= NOW()
    create_if_not_exists index(:scheduled_jobs, [:next_run_at],
                           where: "enabled = true AND next_run_at IS NOT NULL",
                           name: :scheduled_jobs_due_idx,
                           concurrently: true
                         )

    # M-5: fs_agent_already_scheduled? query:
    #   WHERE job_type = 'spawn_agent' AND prompt_id IS NULL AND config::jsonb->>'agent_file_id' = ?
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS scheduled_jobs_config_agent_file_id_idx
    ON scheduled_jobs ((config::jsonb->>'agent_file_id'))
    WHERE job_type = 'spawn_agent' AND prompt_id IS NULL
    """

    # L-3: project_id FK — used in list_jobs/1 project filter
    create_if_not_exists index(:scheduled_jobs, [:project_id],
                           name: :scheduled_jobs_project_id_idx,
                           concurrently: true
                         )
  end

  def down do
    drop_if_exists index(:scheduled_jobs, [:next_run_at], name: :scheduled_jobs_due_idx)
    execute "DROP INDEX IF EXISTS scheduled_jobs_config_agent_file_id_idx"
    drop_if_exists index(:scheduled_jobs, [:project_id], name: :scheduled_jobs_project_id_idx)
  end
end
