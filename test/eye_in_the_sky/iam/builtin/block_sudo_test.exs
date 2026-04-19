defmodule EyeInTheSky.IAM.Builtin.BlockSudoTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockSudo
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}
  defp policy(cond \\ %{}), do: %Policy{condition: cond}

  test "matches bare sudo" do
    assert BlockSudo.matches?(policy(), ctx("sudo rm -rf /"))
  end

  test "matches doas and pkexec" do
    assert BlockSudo.matches?(policy(), ctx("doas apt install x"))
    assert BlockSudo.matches?(policy(), ctx("pkexec systemctl restart foo"))
  end

  test "matches windows runas" do
    assert BlockSudo.matches?(policy(), ctx("runas /user:Administrator cmd"))
    assert BlockSudo.matches?(policy(), ctx("Start-Process cmd -Verb RunAs"))
  end

  test "does not match sudo inside a string literal" do
    refute BlockSudo.matches?(policy(), ctx("echo 'my pseudocode'"))
  end

  test "allowPatterns can escape the match" do
    p = policy(%{"allowPatterns" => ["^sudo -n brew "]})
    refute BlockSudo.matches?(p, ctx("sudo -n brew install foo"))
  end

  test "ignores non-Bash tools" do
    refute BlockSudo.matches?(policy(), %Context{tool: "Read", resource_content: "sudo rm"})
  end
end
