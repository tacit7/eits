defmodule EyeInTheSky.IAM.Builtin.ProtectEnvVarsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.ProtectEnvVars
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}
  defp policy(cond \\ %{}), do: %Policy{condition: cond}

  test "blocks bare env / printenv / export" do
    assert ProtectEnvVars.matches?(policy(), ctx("env"))
    assert ProtectEnvVars.matches?(policy(), ctx("printenv"))
    assert ProtectEnvVars.matches?(policy(), ctx("export"))
  end

  test "blocks echo of sensitive vars" do
    assert ProtectEnvVars.matches?(policy(), ctx("echo $API_KEY"))
    assert ProtectEnvVars.matches?(policy(), ctx("echo ${SECRET_TOKEN}"))
  end

  test "allows echo of non-sensitive vars" do
    refute ProtectEnvVars.matches?(policy(), ctx("echo $HOME"))
    refute ProtectEnvVars.matches?(policy(), ctx("echo $USER"))
  end

  test "custom sensitiveVarPattern" do
    p = policy(%{"sensitiveVarPattern" => "MY_SECRET"})
    assert ProtectEnvVars.matches?(p, ctx("echo $MY_SECRET_VALUE"))
  end
end
