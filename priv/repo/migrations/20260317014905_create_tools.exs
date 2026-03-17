defmodule EyeInTheSkyWeb.Repo.Migrations.CreateTools do
  use Ecto.Migration

  def change do
    create table(:assistant_tools) do
      add :name, :string, null: false
      add :description, :text
      add :destructive, :boolean, default: false, null: false
      add :requires_approval_default, :boolean, default: false, null: false
      add :active, :boolean, default: true, null: false
      add :inserted_at, :naive_datetime
      add :updated_at, :naive_datetime
    end

    create unique_index(:assistant_tools, [:name])
    create index(:assistant_tools, [:active])

    # Seed initial internal tools
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    execute("""
    INSERT INTO assistant_tools (name, description, destructive, requires_approval_default, active, inserted_at, updated_at) VALUES
      ('search_tasks',        'Search tasks by keyword, state, or project',                    false, false, true, '#{now}', '#{now}'),
      ('read_task',           'Read full details of a task by ID',                             false, false, true, '#{now}', '#{now}'),
      ('update_task',         'Update task state, priority, or description',                   false, true,  true, '#{now}', '#{now}'),
      ('create_note',         'Create a note attached to a session, task, or project',         false, false, true, '#{now}', '#{now}'),
      ('list_sessions',       'List sessions filtered by project, status, or agent',           false, false, true, '#{now}', '#{now}'),
      ('send_dm',             'Send a direct message to a session',                            false, true,  true, '#{now}', '#{now}'),
      ('post_channel_message','Post a message to a team channel',                              false, true,  true, '#{now}', '#{now}'),
      ('spawn_subagent',      'Spawn a child agent to handle a subtask',                       false, true,  true, '#{now}', '#{now}'),
      ('run_shell_command',   'Execute a shell command in the project context',                 true,  true,  true, '#{now}', '#{now}'),
      ('write_file',          'Write or overwrite a file in the project',                      true,  true,  true, '#{now}', '#{now}'),
      ('search_project_files','Search files in the project directory by name or content',      false, false, true, '#{now}', '#{now}'),
      ('create_task',         'Create a new task in a project',                                false, false, true, '#{now}', '#{now}')
    """,
    "DELETE FROM assistant_tools")
  end
end
