defmodule EyeInTheSkyWeb.Repo.Migrations.DeferWorkflowStatePositionUnique do
  use Ecto.Migration

  def up do
    # Drop the immediate unique index so we can replace it with a deferrable constraint.
    # A deferrable constraint is checked at transaction commit, not per-statement,
    # which allows single-pass reordering without the two-pass negative-position workaround.
    execute "DROP INDEX IF EXISTS workflow_states_position_index"

    execute """
    ALTER TABLE workflow_states
    ADD CONSTRAINT workflow_states_position_unique
    UNIQUE (position) DEFERRABLE INITIALLY DEFERRED
    """
  end

  def down do
    execute "ALTER TABLE workflow_states DROP CONSTRAINT IF EXISTS workflow_states_position_unique"

    execute "CREATE UNIQUE INDEX IF NOT EXISTS workflow_states_position_index ON workflow_states (position)"
  end
end
