defmodule EyeInTheSky.Git.Worktrees do
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

    # If the worktree already exists, reuse it without rechecking tree cleanliness
    if worktree_exists?(wt_path) do
      Logger.info("prepare_session_worktree: reusing existing worktree at #{wt_path}")
      {:ok, wt_path}
    else
      with :ok <- check_clean_working_tree(project_path),
           :ok <- ensure_git_worktree(project_path, wt_path, branch) do
        {:ok, wt_path}
      end
    end
  end

  defp worktree_exists?(wt_path) do
    File.dir?(wt_path) and
      (File.dir?(Path.join(wt_path, ".git")) or File.regular?(Path.join(wt_path, ".git")))
  end

  @doc """
  Checks that the repo at `repo_path` has no staged or unstaged changes to tracked files.
  Untracked files are ignored — they don't affect worktree creation since worktrees
  branch from HEAD regardless of untracked content.
  Returns `:ok` or `{:error, :dirty_working_tree}`.
  """
  @spec check_clean_working_tree(String.t()) :: :ok | {:error, :dirty_working_tree}
  def check_clean_working_tree(repo_path) do
    case System.cmd("git", ["-C", repo_path, "status", "--porcelain"], stderr_to_stdout: true) do
      {output, 0} ->
        has_tracked_changes =
          output
          |> String.split("\n", trim: true)
          |> Enum.any?(fn line -> not String.starts_with?(line, "??") end)

        if has_tracked_changes, do: {:error, :dirty_working_tree}, else: :ok

      _ ->
        {:error, :dirty_working_tree}
    end
  end

  @doc """
  Creates or reuses a git worktree at `wt_path` on `branch`. If the worktree path already
  exists and is a valid git directory, reuses it. Returns `:ok` or `{:error, reason}`.
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
          attach_existing_worktree(repo_path, wt_path, branch)
        else
          {:error, output}
        end
    end
  end

  defp attach_existing_worktree(repo_path, wt_path, branch) do
    # Branch exists but path doesn't — attach without -b
    case System.cmd("git", ["-C", repo_path, "worktree", "add", wt_path, branch],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {err, code} -> {:error, {code, err}}
    end
  end

  @doc """
  Creates a `deps` symlink inside `wt_path` pointing to `project_path/deps`.

  Uses a relative path computed from the actual directory structure so the symlink
  is portable. If a `deps` symlink or directory already exists, it is left in place.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec symlink_deps(String.t(), String.t()) :: :ok | {:error, String.t()}
  def symlink_deps(project_path, wt_path) do
    deps_source = Path.join(project_path, "deps")
    deps_link   = Path.join(wt_path, "deps")

    cond do
      match?({:ok, %{type: :symlink}}, File.lstat(deps_link)) ->
        # Symlink already exists (live or dangling). Leave it in place.
        :ok

      File.dir?(deps_link) ->
        # A real deps/ directory already exists. Leave it in place.
        :ok

      not File.dir?(deps_source) ->
        {:error, "deps directory not found at #{deps_source}"}

      true ->
        relative_target = Path.relative_to(deps_source, wt_path)
        # Guard against Path.relative_to returning the absolute path unchanged
        if Path.type(relative_target) == :absolute do
          {:error, "cannot compute relative path from #{wt_path} to #{deps_source}"}
        else
          case File.ln_s(relative_target, deps_link) do
            :ok              -> :ok
            {:error, reason} -> {:error, "symlink failed: #{:file.format_error(reason)}"}
          end
        end
    end
  end
end
