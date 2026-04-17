defmodule EyeInTheSky.IAM.Builtin.BlockPushMasterTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockPushMaster
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  test "matches explicit push to main" do
    assert BlockPushMaster.matches?(%Policy{}, ctx("git push origin main"))
  end

  test "matches explicit push to master" do
    assert BlockPushMaster.matches?(%Policy{}, ctx("git push origin master"))
  end

  test "respects custom protectedBranches" do
    p = %Policy{condition: %{"protectedBranches" => ["release"]}}
    assert BlockPushMaster.matches?(p, ctx("git push origin release"))
    refute BlockPushMaster.matches?(p, ctx("git push origin main"))
  end

  test "ignores non-push git" do
    refute BlockPushMaster.matches?(%Policy{}, ctx("git fetch origin main"))
  end

  test "ignores non-Bash" do
    refute BlockPushMaster.matches?(%Policy{}, %Context{tool: "Read"})
  end
end
