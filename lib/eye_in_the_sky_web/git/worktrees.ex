defmodule EyeInTheSkyWeb.Git.Worktrees do
  @moduledoc """
  Git worktree lifecycle management.

  Handles validating repo state and creating/reusing git worktrees for agent sessions.
  """

  require Logger

  @doc """
  Validates that the repo has no uncommitted changes and creates (or reuses) a worktree.

  Returns `{:ok, worktree_path}` on success, `{:error, reason}` on failure.
  If worktree creation fails when explicitly requested, returns an error — does NOT silently
  fall back to the main project path.
  """
  @spec prepare_session_worktree(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :dirty_working_tree | term()}
  def prepare_session_worktree(project_path, worktree_name) do
    wt_path = Path.join([project_path, ".claude", "worktrees", worktree_name])
    branch = "worktree-#{worktree_name}"

    with :ok <- check_clean_working_tree(project_path),
         :ok <- ensure_git_worktree(project_path, wt_path, branch) do
      {:ok, wt_path}
    end
  end

  @doc """
  Checks that the repo at `repo_path` has no staged or unstaged changes.
  Returns `:ok` or `{:error, :dirty_working_tree}`.
  """
  @spec check_clean_working_tree(String.t()) :: :ok | {:error, :dirty_working_tree}
  def check_clean_working_tree(repo_path) do
    with {_, 0} <-
           System.cmd("git", ["-C", repo_path, "diff", "--quiet"], stderr_to_stdout: true),
         {_, 0} <-
           System.cmd("git", ["-C", repo_path, "diff", "--cached", "--quiet"],
             stderr_to_stdout: true
           ) do
      :ok
    else
      _ -> {:error, :dirty_working_tree}
    end
  end

  @doc """
  Creates a git worktree at `wt_path` on `branch`. If the branch already exists, retries
  without `-b`. Returns `:ok` or `{:error, reason}`.
  """
  @spec ensure_git_worktree(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def ensure_git_worktree(repo_path, wt_path, branch) do
    case System.cmd("git", ["-C", repo_path, "worktree", "add", wt_path, "-b", branch],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {output, _} ->
        if String.contains?(output, "already exists") or
             String.contains?(output, "already checked out") do
          case System.cmd("git", ["-C", repo_path, "worktree", "add", wt_path, branch],
                 stderr_to_stdout: true
               ) do
            {_, 0} -> :ok
            {err, code} -> {:error, {code, err}}
          end
        else
          {:error, output}
        end
    end
  end
end
