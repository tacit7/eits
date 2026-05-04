defmodule EyeInTheSky.IAM.Builtin.BlockHelmTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockHelm
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}
  defp policy(cond \\ nil), do: %Policy{condition: cond}

  test "blocks helm uninstall" do
    assert BlockHelm.matches?(policy(), ctx("helm uninstall my-release"))
  end

  test "blocks helm delete (alias)" do
    assert BlockHelm.matches?(policy(), ctx("helm delete my-release"))
  end

  test "blocks helm rollback" do
    assert BlockHelm.matches?(policy(), ctx("helm rollback my-release 1"))
  end

  test "does not block helm install" do
    refute BlockHelm.matches?(policy(), ctx("helm install my-release ./chart"))
  end

  test "does not block helm upgrade" do
    refute BlockHelm.matches?(policy(), ctx("helm upgrade my-release ./chart"))
  end

  test "does not block helm list" do
    refute BlockHelm.matches?(policy(), ctx("helm list"))
  end

  test "does not match non-Bash tool" do
    refute BlockHelm.matches?(policy(), %Context{tool: "Write", resource_content: "helm uninstall x"})
  end

  test "blockCommands condition adds extra blocked verbs" do
    p = policy(%{"blockCommands" => ["upgrade"]})
    assert BlockHelm.matches?(p, ctx("helm upgrade my-release ./chart"))
    assert BlockHelm.matches?(p, ctx("helm uninstall my-release"))
  end
end
