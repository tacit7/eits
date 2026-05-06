defmodule EyeInTheSky.IAM.Builtin.RequireCommitBeforeStopTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.RequireCommitBeforeStop
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp policy(cond \\ nil), do: %Policy{condition: cond}

  defp ctx(path), do: %Context{event: :stop, project_path: path}

  # ── helpers ─────────────────────────────────────────────────────────────────

  # Creates a temp git repo, optionally leaving it dirty, and runs the test.
  defp with_clean_repo(fun) do
    dir = System.tmp_dir!() |> Path.join("iam_test_clean_#{:rand.uniform(99_999)}")
    File.mkdir_p!(dir)

    System.cmd("git", ["-C", dir, "init"])
    System.cmd("git", ["-C", dir, "config", "user.email", "test@test.com"])
    System.cmd("git", ["-C", dir, "config", "user.name", "Test"])

    # Initial commit so HEAD exists
    File.write!(Path.join(dir, "README.md"), "hello")
    System.cmd("git", ["-C", dir, "add", "."])
    System.cmd("git", ["-C", dir, "commit", "-m", "init"])

    try do
      fun.(dir)
    after
      File.rm_rf!(dir)
    end
  end

  defp with_dirty_repo(type, fun) do
    with_clean_repo(fn dir ->
      case type do
        :untracked ->
          File.write!(Path.join(dir, "new_file.ex"), "untracked")

        :modified ->
          File.write!(Path.join(dir, "README.md"), "modified")

        :staged ->
          File.write!(Path.join(dir, "staged.ex"), "staged")
          System.cmd("git", ["-C", dir, "add", "staged.ex"])
      end

      fun.(dir)
    end)
  end

  # ── non-git / wrong event ────────────────────────────────────────────────────

  test "does not match non-Stop events" do
    refute RequireCommitBeforeStop.matches?(policy(), %Context{
             event: :pre_tool_use,
             project_path: "/tmp"
           })

    refute RequireCommitBeforeStop.matches?(policy(), %Context{
             event: :post_tool_use,
             project_path: "/tmp"
           })
  end

  test "does not match when project_path is nil" do
    refute RequireCommitBeforeStop.matches?(policy(), %Context{event: :stop, project_path: nil})
  end

  test "does not match when project_path is not a git repo" do
    dir = System.tmp_dir!() |> Path.join("iam_not_a_repo_#{:rand.uniform(99_999)}")
    File.mkdir_p!(dir)

    try do
      refute RequireCommitBeforeStop.matches?(policy(), ctx(dir))
    after
      File.rm_rf!(dir)
    end
  end

  # ── clean repo ───────────────────────────────────────────────────────────────

  test "does not match a clean repo" do
    with_clean_repo(fn dir ->
      refute RequireCommitBeforeStop.matches?(policy(), ctx(dir))
    end)
  end

  # ── dirty repo — default behavior ───────────────────────────────────────────

  test "matches when there are untracked files" do
    with_dirty_repo(:untracked, fn dir ->
      assert RequireCommitBeforeStop.matches?(policy(), ctx(dir))
    end)
  end

  test "matches when there are unstaged modifications" do
    with_dirty_repo(:modified, fn dir ->
      assert RequireCommitBeforeStop.matches?(policy(), ctx(dir))
    end)
  end

  test "matches when there are staged but uncommitted changes" do
    with_dirty_repo(:staged, fn dir ->
      assert RequireCommitBeforeStop.matches?(policy(), ctx(dir))
    end)
  end

  # ── checkUntracked condition ─────────────────────────────────────────────────

  test "does not match untracked-only when checkUntracked is false" do
    with_dirty_repo(:untracked, fn dir ->
      p = policy(%{"checkUntracked" => false})
      refute RequireCommitBeforeStop.matches?(p, ctx(dir))
    end)
  end

  test "still matches staged changes when checkUntracked is false" do
    with_dirty_repo(:staged, fn dir ->
      p = policy(%{"checkUntracked" => false})
      assert RequireCommitBeforeStop.matches?(p, ctx(dir))
    end)
  end

  # ── ignorePaths condition ────────────────────────────────────────────────────

  test "does not match when the only dirty file is in ignorePaths" do
    with_clean_repo(fn dir ->
      File.write!(Path.join(dir, "ignored.ex"), "content")
      p = policy(%{"ignorePaths" => ["ignored.ex"]})
      refute RequireCommitBeforeStop.matches?(p, ctx(dir))
    end)
  end

  test "still matches when only some files are in ignorePaths" do
    with_clean_repo(fn dir ->
      File.write!(Path.join(dir, "ignored.ex"), "ignored")
      File.write!(Path.join(dir, "important.ex"), "not ignored")
      p = policy(%{"ignorePaths" => ["ignored.ex"]})
      assert RequireCommitBeforeStop.matches?(p, ctx(dir))
    end)
  end
end
