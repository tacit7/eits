defmodule EyeInTheSky.IAM.Builtin.BlockRmRfTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockRmRf
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}
  defp policy(cond \\ %{}), do: %Policy{condition: cond}

  test "blocks rm -rf /" do
    assert BlockRmRf.matches?(policy(), ctx("rm -rf /"))
  end

  test "blocks rm -rf $HOME and ~" do
    assert BlockRmRf.matches?(policy(), ctx("rm -rf $HOME"))
    assert BlockRmRf.matches?(policy(), ctx("rm -rf ~"))
  end

  test "blocks rm -rf /etc" do
    assert BlockRmRf.matches?(policy(), ctx("rm -rf /etc/passwd.d"))
  end

  test "allows rm -rf of a local dir" do
    refute BlockRmRf.matches?(policy(), ctx("rm -rf ./build"))
  end

  test "allowPaths escapes the deny for exact match" do
    p = policy(%{"allowPaths" => ["/tmp/scratch"]})
    refute BlockRmRf.matches?(p, ctx("rm -rf /tmp/scratch"))
  end

  test "allowPaths escapes for child of allow dir" do
    p = policy(%{"allowPaths" => ["/tmp/scratch"]})
    refute BlockRmRf.matches?(p, ctx("rm -rf /tmp/scratch/build"))
  end

  test "allowPaths does not permit sibling by substring (boundary check)" do
    p = policy(%{"allowPaths" => ["/tmp/scratch"]})
    # The target /tmp/scratch-evil must NOT be allowed even though
    # "/tmp/scratch" is a substring of it. However this is also not a
    # dangerous_targets match, so matches? stays false for a different
    # reason; use /etc to get there.
    # Use a case where the allowPath is a prefix string of a dangerous
    # target: allow /etc/foo, deny rm -rf /etc/foobar
    p2 = policy(%{"allowPaths" => ["/etc/foo"]})
    assert BlockRmRf.matches?(p2, ctx("rm -rf /etc/foobar"))
  end

  test "requires both -r and -f flags" do
    refute BlockRmRf.matches?(policy(), ctx("rm -f /etc/hosts"))
    refute BlockRmRf.matches?(policy(), ctx("rm /"))
  end
end
