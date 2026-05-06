defmodule EyeInTheSky.IAM.Builtin.BlockKubectlTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockKubectl
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}
  defp policy(cond \\ nil), do: %Policy{condition: cond}

  test "blocks kubectl delete" do
    assert BlockKubectl.matches?(policy(), ctx("kubectl delete pod my-pod"))
  end

  test "blocks kubectl drain" do
    assert BlockKubectl.matches?(policy(), ctx("kubectl drain node-1 --ignore-daemonsets"))
  end

  test "blocks kubectl cordon" do
    assert BlockKubectl.matches?(policy(), ctx("kubectl cordon node-1"))
  end

  test "blocks kubectl exec" do
    assert BlockKubectl.matches?(policy(), ctx("kubectl exec -it my-pod -- /bin/bash"))
  end

  test "blocks kubectl rollout" do
    assert BlockKubectl.matches?(policy(), ctx("kubectl rollout restart deployment/app"))
  end

  test "does not block kubectl get" do
    refute BlockKubectl.matches?(policy(), ctx("kubectl get pods"))
  end

  test "does not block kubectl describe" do
    refute BlockKubectl.matches?(policy(), ctx("kubectl describe pod my-pod"))
  end

  test "does not block kubectl logs" do
    refute BlockKubectl.matches?(policy(), ctx("kubectl logs my-pod"))
  end

  test "does not match non-Bash tool" do
    refute BlockKubectl.matches?(policy(), %Context{
             tool: "Write",
             resource_content: "kubectl delete pod x"
           })
  end

  test "allowVerbs escapes the block" do
    p = policy(%{"allowVerbs" => ["exec"]})
    refute BlockKubectl.matches?(p, ctx("kubectl exec -it my-pod -- bash"))
    assert BlockKubectl.matches?(p, ctx("kubectl delete pod my-pod"))
  end
end
