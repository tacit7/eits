defmodule EyeInTheSky.IAM.Builtin.WarnDestructiveSqlTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.WarnDestructiveSql
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  test "matches psql DROP TABLE" do
    assert WarnDestructiveSql.matches?(%Policy{}, ctx(~s|psql -c "DROP TABLE users"|))
  end

  test "matches mysql TRUNCATE" do
    assert WarnDestructiveSql.matches?(%Policy{}, ctx(~s|mysql -e "TRUNCATE TABLE logs"|))
  end

  test "matches DELETE without WHERE" do
    assert WarnDestructiveSql.matches?(%Policy{}, ctx(~s|sqlite3 x.db "DELETE FROM users"|))
  end

  test "does not match DELETE with WHERE" do
    refute WarnDestructiveSql.matches?(%Policy{}, ctx(~s|psql -c "DELETE FROM users WHERE id=1"|))
  end

  test "does not match DROP without a DB client" do
    refute WarnDestructiveSql.matches?(%Policy{}, ctx("echo 'DROP TABLE users'"))
  end

  describe "with a real sqlite3 db file" do
    setup do
      db_path = Path.join(System.tmp_dir!(), "iam_test_#{System.unique_integer([:positive])}.db")
      # Create an empty SQLite DB — sqlite3 creates the file on open when no schema is given
      {_, 0} = System.cmd("sqlite3", [db_path, ".quit"])
      on_exit(fn -> File.rm(db_path) end)
      {:ok, db_path: db_path}
    end

    test "matches DROP TABLE against real db path", %{db_path: db_path} do
      cmd = ~s|sqlite3 "#{db_path}" "DROP TABLE IF EXISTS test_table"|
      assert WarnDestructiveSql.matches?(%Policy{}, ctx(cmd))
    end

    test "matches DELETE without WHERE against real db path", %{db_path: db_path} do
      cmd = ~s|sqlite3 "#{db_path}" "DELETE FROM test_table"|
      assert WarnDestructiveSql.matches?(%Policy{}, ctx(cmd))
    end

    test "does not match safe SELECT against real db path", %{db_path: db_path} do
      cmd = ~s|sqlite3 "#{db_path}" "SELECT * FROM test_table"|
      refute WarnDestructiveSql.matches?(%Policy{}, ctx(cmd))
    end

    test "does not match DELETE with WHERE against real db path", %{db_path: db_path} do
      cmd = ~s|sqlite3 "#{db_path}" "DELETE FROM test_table WHERE id = 1"|
      refute WarnDestructiveSql.matches?(%Policy{}, ctx(cmd))
    end
  end
end
