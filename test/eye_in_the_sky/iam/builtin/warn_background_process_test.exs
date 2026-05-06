defmodule EyeInTheSky.IAM.Builtin.WarnBackgroundProcessTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.WarnBackgroundProcess
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  test "matches command ending with &" do
    assert WarnBackgroundProcess.matches?(%Policy{}, ctx("mix phx.server &"))
  end

  test "matches nohup command with &" do
    assert WarnBackgroundProcess.matches?(
             %Policy{},
             ctx("nohup mix phx.server > /tmp/log 2>&1 &")
           )
  end

  test "matches & followed by disown" do
    assert WarnBackgroundProcess.matches?(%Policy{}, ctx("my-server & disown"))
  end

  test "does not match && (logical AND)" do
    refute WarnBackgroundProcess.matches?(%Policy{}, ctx("mix deps.get && mix compile"))
  end

  test "does not match plain command with no &" do
    refute WarnBackgroundProcess.matches?(%Policy{}, ctx("mix compile"))
  end

  test "does not match non-Bash tool" do
    refute WarnBackgroundProcess.matches?(%Policy{}, %Context{
             tool: "Write",
             resource_content: "server &"
           })
  end

  test "does not match 2>&1 stderr redirect" do
    refute WarnBackgroundProcess.matches?(%Policy{}, ctx("cmd > /tmp/out 2>&1"))
  end
end
