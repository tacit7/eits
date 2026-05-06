defmodule EyeInTheSky.Repo.Migrations.AddRound7PerfIndexes do
  use Ecto.Migration

  # All indexes created CONCURRENTLY to avoid locking writes on live tables.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # H1: compound unique index for subagent_prompts (slug, project_id).
    # The Prompt changeset references :idx_subagent_prompts_slug_project but this
    # index never existed. Without it the unique_constraint/2 match silently fails
    # and callers receive an unmatched DB error instead of a human-readable message.
    # NULL project_id (global prompts) are handled by the existing global slug unique
    # index; this compound index covers per-project slug uniqueness only.
    create_if_not_exists(
      unique_index(:subagent_prompts, [:slug, :project_id],
        name: :idx_subagent_prompts_slug_project,
        where: "project_id IS NOT NULL",
        concurrently: true
      )
    )

    # Fix the global slug unique index name to match the changeset reference.
    # The changeset calls unique_constraint(:slug, name: :idx_subagent_prompts_slug_global)
    # but the existing index is named subagent_prompts_slug_index. Rename it so the
    # Ecto error translation finds the right constraint and returns the right message.
    execute(
      "ALTER INDEX IF EXISTS subagent_prompts_slug_index RENAME TO idx_subagent_prompts_slug_global",
      "ALTER INDEX IF EXISTS idx_subagent_prompts_slug_global RENAME TO subagent_prompts_slug_index"
    )

    # H2/M2: compound index for job_runs to support DISTINCT ON (job_id) ORDER BY started_at DESC.
    # last_run_status_map and last_run_per_job do a full seq scan on 5000+ rows today.
    # (job_id ASC, started_at DESC) lets PostgreSQL resolve DISTINCT ON via an Index Only Scan.
    create_if_not_exists(
      index(:job_runs, [:job_id, "started_at DESC"],
        name: :job_runs_job_id_started_at_idx,
        concurrently: true
      )
    )

    # M2: partial index for list_running_job_ids — only rows with status = 'running'.
    # The existing job_runs_job_id_index covers FK lookups; this partial index speeds
    # up the "currently running" filter which fires on every jobs-page mount.
    create_if_not_exists(
      index(:job_runs, [:job_id],
        name: :job_runs_running_partial_idx,
        where: "status = 'running'",
        concurrently: true
      )
    )
  end

  def down do
    drop_if_exists(index(:job_runs, [:job_id], name: :job_runs_running_partial_idx))

    drop_if_exists(
      index(:job_runs, [:job_id, "started_at DESC"], name: :job_runs_job_id_started_at_idx)
    )

    execute(
      "ALTER INDEX IF EXISTS idx_subagent_prompts_slug_global RENAME TO subagent_prompts_slug_index",
      "ALTER INDEX IF EXISTS subagent_prompts_slug_index RENAME TO idx_subagent_prompts_slug_global"
    )

    drop_if_exists(
      unique_index(:subagent_prompts, [:slug, :project_id],
        name: :idx_subagent_prompts_slug_project
      )
    )
  end
end
