defmodule EyeInTheSky.Repo.Migrations.NormalizeNotesParentType do
  use Ecto.Migration

  def change do
    execute "UPDATE notes SET parent_type = 'task' WHERE parent_type = 'tasks'",
            "UPDATE notes SET parent_type = 'tasks' WHERE parent_type = 'task'"

    execute "UPDATE notes SET parent_type = 'session' WHERE parent_type = 'sessions'",
            "UPDATE notes SET parent_type = 'sessions' WHERE parent_type = 'session'"

    execute "UPDATE notes SET parent_type = 'agent' WHERE parent_type = 'agents'",
            "UPDATE notes SET parent_type = 'agents' WHERE parent_type = 'agent'"

    execute "UPDATE notes SET parent_type = 'project' WHERE parent_type = 'projects'",
            "UPDATE notes SET parent_type = 'projects' WHERE parent_type = 'project'"

    execute "UPDATE notes SET parent_type = 'channel' WHERE parent_type = 'channels'",
            "UPDATE notes SET parent_type = 'channels' WHERE parent_type = 'channel'"
  end
end
