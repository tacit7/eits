defmodule EyeInTheSky.IAM.Builtin.BlockWorkOnMain do
  @moduledoc """
  Deny mutating git operations (commit/merge/rebase/cherry-pick) when the
  current branch is a protected branch. Uses `git rev-parse
  --abbrev-ref HEAD` against `Context.project_path`.

  Supports `"protectedBranches"`. Defaults to `["main", "master"]`.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  require Logger

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @default_branches ~w(main master)

  @mutating_re ~r/\bgit\s+(?:commit|merge|rebase|cherry-pick|am|revert|reset\s+--hard)\b/

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd, project_path: cwd})
      when is_binary(cmd) and is_binary(cwd) do
    if Regex.match?(@mutating_re, cmd) do
      # Prefer the `cd` target from the command itself — this ensures worktree
      # commits (e.g. `cd .claude/worktrees/foo && git commit`) are evaluated
      # against the worktree's HEAD rather than the project root's HEAD.
      effective_cwd = extract_cd_target(cmd, cwd) || cwd
      current_branch(effective_cwd) in protected_branches(p)
    else
      false
    end
  end

  def matches?(_, _), do: false

  # Extract the first `cd <path>` target from a compound shell command.
  # Returns nil when no cd is found so the caller falls back to project_path.
  defp extract_cd_target(cmd, base_cwd) do
    case Regex.run(~r/(?:^|[;&|]\s*)cd\s+([^\s;&|]+)/, cmd) do
      [_, raw_path] ->
        expanded = Path.expand(raw_path, base_cwd)
        if File.dir?(expanded), do: expanded, else: nil

      _ ->
        nil
    end
  end

  defp current_branch(cwd) do
    # symbolic-ref handles unborn branches; rev-parse fails when HEAD has no
    # commits yet. Prefer symbolic-ref; fall back to rev-parse for detached
    # HEADs (which symbolic-ref cannot resolve).
    case System.cmd("git", ["symbolic-ref", "--short", "HEAD"], cd: cwd, stderr_to_stdout: true) do
      {out, 0} ->
        String.trim(out)

      _ ->
        case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"], cd: cwd, stderr_to_stdout: true) do
          {out, 0} -> String.trim(out)
          _ -> nil
        end
    end
  rescue
    e in ErlangError ->
      Logger.warning("BlockWorkOnMain: failed to determine current branch in #{cwd}: #{inspect(e)}")
      nil
  end

  defp protected_branches(%Policy{condition: %{} = cond}) do
    Map.get(cond, "protectedBranches") || Map.get(cond, :protectedBranches) || @default_branches
  end

  defp protected_branches(_), do: @default_branches
end
