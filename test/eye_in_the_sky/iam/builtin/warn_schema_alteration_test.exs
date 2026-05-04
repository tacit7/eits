defmodule EyeInTheSky.IAM.Builtin.WarnSchemaAlterationTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.WarnSchemaAlteration
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  test "matches ALTER TABLE via psql" do
    assert WarnSchemaAlteration.matches?(%Policy{}, ctx(~s|psql -c "ALTER TABLE users ADD COLUMN age INT"|))
  end

  test "matches DROP COLUMN via mysql" do
    assert WarnSchemaAlteration.matches?(%Policy{}, ctx(~s|mysql -e "ALTER TABLE orders DROP COLUMN legacy"|))
  end

  test "matches RENAME TABLE via sqlite3" do
    assert WarnSchemaAlteration.matches?(%Policy{}, ctx(~s|sqlite3 app.db "RENAME TABLE old TO new"|))
  end

  test "matches RENAME COLUMN" do
    assert WarnSchemaAlteration.matches?(%Policy{}, ctx(~s|psql -c "ALTER TABLE t RENAME COLUMN a TO b"|))
  end

  test "matches MODIFY COLUMN via mysql" do
    assert WarnSchemaAlteration.matches?(%Policy{}, ctx(~s|mysql -e "ALTER TABLE t MODIFY COLUMN col VARCHAR(255)"|))
  end

  test "does not match without a DB client" do
    refute WarnSchemaAlteration.matches?(%Policy{}, ctx("echo 'ALTER TABLE foo'"))
  end

  test "does not match SELECT via psql" do
    refute WarnSchemaAlteration.matches?(%Policy{}, ctx(~s|psql -c "SELECT * FROM users"|))
  end

  test "does not match non-Bash tool" do
    refute WarnSchemaAlteration.matches?(%Policy{}, %Context{tool: "Write", resource_content: "psql -c 'ALTER TABLE x'"})
  end
end
