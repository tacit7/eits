defmodule EyeInTheSky.IAM.Builtin.WarnGitStashDropTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.WarnGitStashDrop
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  test "matches git stash drop" do
    assert WarnGitStashDrop.matches?(%Policy{}, ctx("git stash drop"))
  end

  test "matches git stash drop with stash ref" do
    assert WarnGitStashDrop.matches?(%Policy{}, ctx("git stash drop stash@{0}"))
  end

  test "matches git stash clear" do
    assert WarnGitStashDrop.matches?(%Policy{}, ctx("git stash clear"))
  end

  test "does not match git stash pop" do
    refute WarnGitStashDrop.matches?(%Policy{}, ctx("git stash pop"))
  end

  test "does not match git stash list" do
    refute WarnGitStashDrop.matches?(%Policy{}, ctx("git stash list"))
  end

  test "does not match git stash push" do
    refute WarnGitStashDrop.matches?(%Policy{}, ctx("git stash push -m 'wip'"))
  end

  test "does not match non-Bash tool" do
    ctx = %Context{tool: "Write", resource_content: "git stash drop"}
    refute WarnGitStashDrop.matches?(%Policy{}, ctx)
  end
end
