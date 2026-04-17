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

  @tag :tmp_dir
  test "blocks symlink inside cwd pointing outside", %{tmp_dir: dir} do
    # Link inside the project points at /etc. Naive Path.expand would
    # leave the resolved path inside `dir` and miss the escape.
    link = Path.join(dir, "escape")
    :ok = File.ln_s("/etc", link)

    ctx = %Context{tool: "Read", resource_path: link, project_path: dir}
    assert BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  @tag :tmp_dir
  test "allows symlink inside cwd pointing inside cwd", %{tmp_dir: dir} do
    inner = Path.join(dir, "real")
    File.mkdir_p!(inner)
    link = Path.join(dir, "lnk")
    :ok = File.ln_s(inner, link)

    ctx = %Context{tool: "Read", resource_path: link, project_path: dir}
    refute BlockReadOutsideCwd.matches?(policy(), ctx)
  end
end
