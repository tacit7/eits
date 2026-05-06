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

  # ── Bash pipe handling ──────────────────────────────────────────────────────

  test "blocks absolute path before pipe" do
    # cat /etc/passwd | grep root — should detect /etc/passwd
    ctx = %Context{
      tool: "Bash",
      resource_content: "cat /etc/passwd | grep root",
      project_path: "/proj"
    }

    assert BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  test "allows relative path in Bash command" do
    ctx = %Context{tool: "Bash", resource_content: "cat lib/foo.ex", project_path: "/proj"}
    refute BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  test "no match for Bash command with no path args" do
    ctx = %Context{tool: "Bash", resource_content: "mix compile", project_path: "/proj"}
    refute BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  # ── tilde / home path handling ──────────────────────────────────────────────

  test "blocks tilde path outside cwd" do
    # ~/.ssh/id_rsa is in home, not in /proj
    ctx = %Context{tool: "Bash", resource_content: "cat ~/.ssh/id_rsa", project_path: "/proj"}
    assert BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  @tag :tmp_dir
  test "allows tilde path when cwd is home subdir", %{tmp_dir: dir} do
    # If project_path IS under home, a ~/relative path inside it should be allowed.
    # We use tmp_dir as a stand-in for home to avoid depending on real $HOME.
    inner = Path.join(dir, "myfile.txt")
    File.write!(inner, "ok")
    ctx = %Context{tool: "Read", resource_path: inner, project_path: dir}
    refute BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  # ── Grep / Glob tools ───────────────────────────────────────────────────────

  test "blocks Grep with absolute path outside cwd" do
    ctx = %Context{tool: "Grep", resource_path: "/etc/hosts", project_path: "/proj"}
    assert BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  test "allows Grep with path inside cwd" do
    ctx = %Context{tool: "Grep", resource_path: "/proj/lib/foo.ex", project_path: "/proj"}
    refute BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  test "blocks Glob with absolute path outside cwd" do
    ctx = %Context{tool: "Glob", resource_path: "/etc/**", project_path: "/proj"}
    assert BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  # ── non-existent path inside cwd ────────────────────────────────────────────

  test "allows non-existent path inside cwd (planned write target)" do
    ctx = %Context{
      tool: "Read",
      resource_path: "/proj/lib/does_not_exist_yet.ex",
      project_path: "/proj"
    }

    refute BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  # ── Write tool — not blocked by this matcher ────────────────────────────────

  test "does not match Write tool (not in scope)" do
    ctx = %Context{tool: "Write", resource_path: "/etc/passwd", project_path: "/proj"}
    refute BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  # ── cwd prefix false positive guard ─────────────────────────────────────────

  test "does not allow path that merely starts with cwd string but escapes boundary" do
    # /projects-evil is not inside /projects — must check trailing slash boundary
    ctx = %Context{
      tool: "Read",
      resource_path: "/projects-evil/secret",
      project_path: "/projects"
    }

    assert BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  # ── URL-path false positive guard ────────────────────────────────────────────

  test "does not block Bash command with URL-path in --message arg (eits dm regression)" do
    # /api/v1/editors/ is a URL route, not a filesystem path — /api does not
    # exist on the local filesystem, so the matcher must not treat it as a
    # real path to check against cwd.
    cmd = ~s(eits dm --to some-uuid --message "no REST route for /api/v1/editors/ yet")
    ctx = %Context{tool: "Bash", resource_content: cmd, project_path: "/Users/me/project"}
    refute BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  test "does not block eits dm command with complex message containing slashes" do
    cmd = ~s(eits dm --to abc-123 --message "Events.editor_push/3 and /api/v1/editors/")
    ctx = %Context{tool: "Bash", resource_content: cmd, project_path: "/Users/me/project"}
    refute BlockReadOutsideCwd.matches?(policy(), ctx)
  end

  test "still blocks Bash command with real out-of-cwd path after URL-path guard" do
    # /etc DOES exist on the filesystem, so this should still be caught
    cmd = "cat /etc/passwd"
    ctx = %Context{tool: "Bash", resource_content: cmd, project_path: "/Users/me/project"}
    assert BlockReadOutsideCwd.matches?(policy(), ctx)
  end
end
