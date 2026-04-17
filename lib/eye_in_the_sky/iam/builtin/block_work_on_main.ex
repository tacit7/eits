defmodule EyeInTheSky.IAM.Builtin.BlockWorkOnMain do
  @moduledoc """
  Deny mutating git operations (commit/merge/rebase/cherry-pick) when the
  current branch is a protected branch. Uses `git rev-parse
  --abbrev-ref HEAD` against `Context.project_path`.

  Supports `"protectedBranches"`. Defaults to `["main", "master"]`.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @default_branches ~w(main master)

  @mutating_re ~r/\bgit\s+(?:commit|merge|rebase|cherry-pick|am|revert|reset\s+--hard)\b/

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd, project_path: cwd})
      when is_binary(cmd) and is_binary(cwd) do
    if Regex.match?(@mutating_re, cmd) do
      current_branch(cwd) in protected_branches(p)
    else
      false
    end
  end

  def matches?(_, _), do: false

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
    _ -> nil
  end

  defp protected_branches(%Policy{condition: %{} = cond}) do
    Map.get(cond, "protectedBranches") || Map.get(cond, :protectedBranches) || @default_branches
  end

  defp protected_branches(_), do: @default_branches
end
