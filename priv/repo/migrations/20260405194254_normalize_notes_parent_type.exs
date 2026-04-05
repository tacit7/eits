defmodule EyeInTheSky.Repo.Migrations.NormalizeNotesParentType do
  use Ecto.Migration

  def change do
    execute(
      "UPDATE notes SET parent_type = 'task' WHERE parent_type = 'tasks'",
      "UPDATE notes SET parent_type = 'tasks' WHERE parent_type = 'task'"
    )
  end
end
