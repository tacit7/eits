defmodule EyeInTheSky.Repo.Migrations.AddAgentIdAndArchivedIndexesToTasks do
  use Ecto.Migration

  def change do
    create index(:tasks, [:agent_id])
    create index(:tasks, [:archived])
  end
end
