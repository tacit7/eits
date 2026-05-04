defmodule EyeInTheSky.IAM.Builtin.BlockForcePush do
  @moduledoc """
  Deny Bash invocations of `git push --force` or `git push -f`.

  Force-pushing rewrites remote history and can permanently destroy commits
  for collaborators. This is distinct from `block_push_master` which guards
  specific branch names — this matcher blocks the force flag regardless of
  branch.

  Supports an `"allowBranches"` condition entry — a list of branch name
  strings (exact match) where force-push is permitted (e.g. personal
  feature branches). When the command includes a matching branch name the
  policy does not fire.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  # Must not match --force-with-lease — use negative lookahead after --force
  @force_re ~r/\bgit\s+push\b.*\s(?:--force(?!-with-lease\b)|-f\b)/

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    if Regex.match?(@force_re, cmd) do
      not allowed?(cmd, p)
    else
      false
    end
  end

  def matches?(_, _), do: false

  defp allowed?(cmd, %Policy{condition: %{} = cond}) do
    branches = Map.get(cond, "allowBranches") || Map.get(cond, :allowBranches) || []

    Enum.any?(branches, fn branch when is_binary(branch) ->
      String.contains?(cmd, branch)
    end)
  end

  defp allowed?(_, _), do: false
end
