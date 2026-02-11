defmodule EyeInTheSkyWeb.SchemaLoader do
  @moduledoc """
  Loads the schema from production EITS database into the test database.

  Since the Go MCP server owns the schema and this Phoenix app
  doesn't use migrations, we copy the schema from the prod database.
  """

  @prod_db_path "~/.config/eye-in-the-sky/eits.db"

  def load_schema! do
    test_db_path = Application.get_env(:eye_in_the_sky_web, EyeInTheSkyWeb.Repo)[:database]
    prod_db = Path.expand(@prod_db_path)

    unless File.exists?(prod_db) do
      raise """
      Production database not found at: #{prod_db}

      The test database needs to copy the schema from production.
      Make sure EITS is initialized by running the Go MCP server at least once.
      """
    end

    # Copy the entire database file (simpler and preserves everything)
    File.cp!(prod_db, test_db_path)

    # Clear all data (keep schema only)
    clear_data_cmd = """
    sqlite3 #{test_db_path} "
    PRAGMA foreign_keys = OFF;
    DELETE FROM projects;
    DELETE FROM agents;
    DELETE FROM sessions;
    DELETE FROM messages;
    DELETE FROM channels;
    DELETE FROM channel_members;
    DELETE FROM message_reactions;
    DELETE FROM file_attachments;
    DELETE FROM notes;
    DELETE FROM tasks;
    DELETE FROM task_states;
    DELETE FROM workflow_states;
    DELETE FROM prompts;
    DELETE FROM commits;
    DELETE FROM bookmarks;
    PRAGMA foreign_keys = ON;
    VACUUM;
    "
    """

    {_output, _exit_code} = System.cmd("sh", ["-c", clear_data_cmd], stderr_to_stdout: true)

    :ok
  end

  def reset_database! do
    test_db_path = Application.get_env(:eye_in_the_sky_web, EyeInTheSkyWeb.Repo)[:database]

    # Delete and recreate the database
    if File.exists?(test_db_path) do
      File.rm!(test_db_path)
    end

    File.touch!(test_db_path)
    load_schema!()
  end

  def schema_loaded? do
    # Check if the sessions table exists
    case Ecto.Adapters.SQL.query(
           EyeInTheSkyWeb.Repo,
           "SELECT name FROM sqlite_master WHERE type='table' AND name='sessions'",
           []
         ) do
      {:ok, %{rows: [[_name]]}} -> true
      _ -> false
    end
  end
end
