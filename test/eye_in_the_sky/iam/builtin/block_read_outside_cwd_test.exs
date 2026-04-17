defmodule EyeInTheSky.IAM.Builtin.BlockReadOutsideCwdTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockReadOutsideCwd
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp policy, do: %Policy{}

  test "allows reads inside cwd" do
    ctx = %Context{tool: "Read", resource_path: "/proj/a.ex", project_path: "/proj"}
    refute BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  test "blocks reads outside cwd" do
    ctx = %Context{tool: "Read", resource_path: "/etc/passwd", project_path: "/proj"}
    assert BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  test "blocks path-escape via .." do
    ctx = %Context{tool: "Read", resource_path: "/proj/../etc/passwd", project_path: "/proj"}
    assert BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  test "handles Bash absolute path arg" do
    ctx = %Context{tool: "Bash", resource_content: "cat /etc/hosts", project_path: "/proj"}
    assert BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  test "no-op without project_path" do
    ctx = %Context{tool: "Read", resource_path: "/etc/passwd"}
    refute BlockReadOutsideCwd.matches?(policy(), ctx)
  end
end
