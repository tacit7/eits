defmodule EyeInTheSky.Agents.AgentManager.SpawnParamsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Agents.AgentManager.SpawnParams

  test "Codex spawns default to bypassing approvals and sandbox" do
    opts = SpawnParams.build(%{"provider" => "codex"}, nil)

    assert opts[:bypass_sandbox] == true
    assert "--dangerously-bypass-approvals-and-sandbox" in EyeInTheSky.Codex.CLI.build_args(opts)
  end

  test "Codex spawns preserve an explicit opt-out" do
    opts = SpawnParams.build(%{"provider" => "codex", "bypass_sandbox" => false}, nil)

    assert opts[:bypass_sandbox] == false
    refute "--dangerously-bypass-approvals-and-sandbox" in EyeInTheSky.Codex.CLI.build_args(opts)
  end

  test "other providers keep their existing bypass defaults" do
    for provider <- [nil, "claude", "pi"] do
      assert SpawnParams.build(%{"provider" => provider}, nil)[:bypass_sandbox] == false
    end
  end
end
