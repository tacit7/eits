defmodule EyeInTheSky.IAM.Builtin.WarnAllFilesStagedTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.WarnAllFilesStaged
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  test "matches git add ." do
    assert WarnAllFilesStaged.matches?(%Policy{}, ctx("git add ."))
  end

  test "matches git add -A" do
    assert WarnAllFilesStaged.matches?(%Policy{}, ctx("git add -A"))
  end

  test "matches git add --all" do
    assert WarnAllFilesStaged.matches?(%Policy{}, ctx("git add --all"))
  end

  test "matches git add -u" do
    assert WarnAllFilesStaged.matches?(%Policy{}, ctx("git add -u"))
  end

  test "matches git add *" do
    assert WarnAllFilesStaged.matches?(%Policy{}, ctx("git add *"))
  end

  test "does not match git add with specific file" do
    refute WarnAllFilesStaged.matches?(%Policy{}, ctx("git add lib/foo.ex"))
  end

  test "does not match git add with specific directory" do
    refute WarnAllFilesStaged.matches?(%Policy{}, ctx("git add lib/"))
  end

  test "does not match non-Bash tool" do
    ctx = %Context{tool: "Write", resource_content: "git add ."}
    refute WarnAllFilesStaged.matches?(%Policy{}, ctx)
  end

  test "does not match unrelated command" do
    refute WarnAllFilesStaged.matches?(%Policy{}, ctx("mix test"))
  end
end
