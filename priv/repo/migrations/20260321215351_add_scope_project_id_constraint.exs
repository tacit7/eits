defmodule EyeInTheSky.Repo.Migrations.AddScopeProjectIdConstraint do
  use Ecto.Migration

  def change do
    # Global definitions must have NULL project_id
    create constraint(:agent_definitions, :global_must_have_null_project,
             check: "NOT (scope = 'global' AND project_id IS NOT NULL)"
           )

    # Project definitions must have a project_id
    create constraint(:agent_definitions, :project_must_have_project_id,
             check: "NOT (scope = 'project' AND project_id IS NULL)"
           )
  end
end
