defmodule EyeInTheSkyWeb.Git.WorktreesTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Git.Worktrees

  @moduletag :tmp_dir

  describe "check_clean_working_tree/1" do
    test "returns :ok for a clean repo", %{tmp_dir: tmp_dir} do
      init_git_repo(tmp_dir)
      assert :ok = Worktrees.check_clean_working_tree(tmp_dir)
    end

    test "returns error for unstaged changes to tracked files", %{tmp_dir: tmp_dir} do
      init_git_repo(tmp_dir)
      # Modify the already-tracked README.md
      File.write!(Path.join(tmp_dir, "README.md"), "modified")
      assert {:error, :dirty_working_tree} = Worktrees.check_clean_working_tree(tmp_dir)
    end

    test "returns error for staged changes", %{tmp_dir: tmp_dir} do
      init_git_repo(tmp_dir)
      File.write!(Path.join(tmp_dir, "README.md"), "staged change")
      System.cmd("git", ["-C", tmp_dir, "add", "README.md"])
      assert {:error, :dirty_working_tree} = Worktrees.check_clean_working_tree(tmp_dir)
    end

    test "returns error for untracked files", %{tmp_dir: tmp_dir} do
      init_git_repo(tmp_dir)
      File.write!(Path.join(tmp_dir, "untracked.txt"), "new file")
      assert {:error, :dirty_working_tree} = Worktrees.check_clean_working_tree(tmp_dir)
    end
  end

  describe "prepare_session_worktree/2" do
    test "creates worktree in clean repo", %{tmp_dir: tmp_dir} do
      init_git_repo(tmp_dir)

      assert {:ok, wt_path} = Worktrees.prepare_session_worktree(tmp_dir, "test-wt")
      assert wt_path == Path.join([tmp_dir, ".claude", "worktrees", "test-wt"])
      assert File.dir?(wt_path)
    end

    test "reuses existing worktree", %{tmp_dir: tmp_dir} do
      init_git_repo(tmp_dir)

      assert {:ok, wt_path} = Worktrees.prepare_session_worktree(tmp_dir, "test-wt")
      assert File.dir?(wt_path)

      # Second call should reuse, not error
      assert {:ok, ^wt_path} = Worktrees.prepare_session_worktree(tmp_dir, "test-wt")
    end

    test "returns error when repo is dirty", %{tmp_dir: tmp_dir} do
      init_git_repo(tmp_dir)
      File.write!(Path.join(tmp_dir, "README.md"), "modified")

      assert {:error, :dirty_working_tree} =
               Worktrees.prepare_session_worktree(tmp_dir, "test-wt")
    end
  end

  defp init_git_repo(dir) do
    System.cmd("git", ["-C", dir, "init"])
    System.cmd("git", ["-C", dir, "config", "user.email", "test@test.com"])
    System.cmd("git", ["-C", dir, "config", "user.name", "Test"])
    File.write!(Path.join(dir, "README.md"), "init")
    System.cmd("git", ["-C", dir, "add", "."])
    System.cmd("git", ["-C", dir, "commit", "-m", "init"])
  end
end
