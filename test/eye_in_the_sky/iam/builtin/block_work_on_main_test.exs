defmodule EyeInTheSky.IAM.Builtin.BlockWorkOnMainTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockWorkOnMain
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @tag :tmp_dir
  test "matches git commit on main branch", %{tmp_dir: dir} do
    init_repo!(dir, "main")
    ctx = %Context{tool: "Bash", resource_content: "git commit -m x", project_path: dir}
    assert BlockWorkOnMain.matches?(%Policy{}, ctx)
  end

  @tag :tmp_dir
  test "does not match on a feature branch", %{tmp_dir: dir} do
    init_repo!(dir, "feature/x")
    ctx = %Context{tool: "Bash", resource_content: "git commit -m x", project_path: dir}
    refute BlockWorkOnMain.matches?(%Policy{}, ctx)
  end

  test "ignores non-mutating git" do
    ctx = %Context{tool: "Bash", resource_content: "git status", project_path: "/tmp"}
    refute BlockWorkOnMain.matches?(%Policy{}, ctx)
  end

  test "ignores non-Bash" do
    refute BlockWorkOnMain.matches?(%Policy{}, %Context{tool: "Read"})
  end

  defp init_repo!(dir, branch) do
    System.cmd("git", ["init"], cd: dir, stderr_to_stdout: true)
    System.cmd("git", ["symbolic-ref", "HEAD", "refs/heads/" <> branch], cd: dir, stderr_to_stdout: true)
  end
end
