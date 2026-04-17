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
end
