defmodule EyeInTheSky.IAM.Builtin.BlockForcePushTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockForcePush
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}
  defp policy(cond \\ nil), do: %Policy{condition: cond}

  test "matches git push --force" do
    assert BlockForcePush.matches?(policy(), ctx("git push origin main --force"))
  end

  test "matches git push -f shorthand" do
    assert BlockForcePush.matches?(policy(), ctx("git push origin main -f"))
  end

  test "matches git push --force before branch" do
    assert BlockForcePush.matches?(policy(), ctx("git push --force origin feature"))
  end

  test "does not match plain git push" do
    refute BlockForcePush.matches?(policy(), ctx("git push origin main"))
  end

  test "does not match git push --force-with-lease" do
    # --force-with-lease is the safe alternative and must not be blocked
    refute BlockForcePush.matches?(policy(), ctx("git push --force-with-lease origin main"))
  end

  test "does not match non-Bash tool" do
    ctx = %Context{tool: "Write", resource_content: "git push --force"}
    refute BlockForcePush.matches?(policy(), ctx)
  end

  test "allowBranches escapes the deny for the listed branch" do
    p = policy(%{"allowBranches" => ["my-feature"]})
    # my-feature is allowed — policy should NOT fire (returns false)
    refute BlockForcePush.matches?(p, ctx("git push --force origin my-feature"))
    # main is not in allowBranches — policy fires
    assert BlockForcePush.matches?(p, ctx("git push --force origin main"))
  end
end
