defmodule EyeInTheSky.Repo.Migrations.AddNotesTaskIndexAndIamFkIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Partial index for task-scoped notes queries (mirrors the project-scoped one
    # added in 20260501053103). note_queries.ex with_notes_count/1 was doing a
    # full filtered scan on notes for every task list view.
    create_if_not_exists index(:notes, [:parent_id],
                           where: "parent_type = 'task'",
                           name: :notes_task_parent_idx,
                           concurrently: true
                         )

    # IAM decisions FK columns were created without indexes in 20260417214321.
    # Audit rows accumulate quickly; queries filtered by either FK were table-scanning.
    create_if_not_exists index(:iam_decisions, [:winning_policy_id],
                           where: "winning_policy_id IS NOT NULL",
                           concurrently: true
                         )

    create_if_not_exists index(:iam_decisions, [:project_id],
                           where: "project_id IS NOT NULL",
                           concurrently: true
                         )
  end

  def down do
    drop_if_exists index(:iam_decisions, [:project_id], where: "project_id IS NOT NULL")

    drop_if_exists index(:iam_decisions, [:winning_policy_id],
                     where: "winning_policy_id IS NOT NULL"
                   )

    drop_if_exists index(:notes, [:parent_id], name: :notes_task_parent_idx)
  end
end
