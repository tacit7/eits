defmodule EyeInTheSky.IAM.Builtin.BlockPushMaster do
  @moduledoc """
  Deny `git push` to a protected branch.

  Detects explicit `git push <remote> <branch>` and `git push --force`
  variants. Also flags `git push` with no args when the current branch
  (via `git rev-parse --abbrev-ref HEAD`) is protected.

  Supports `"protectedBranches"` — list of branch names. Defaults to
  `["main", "master"]`.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  require Logger

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @default_branches ~w(main master)

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd} = ctx)
      when is_binary(cmd) do
    if git_push?(cmd) do
      branches = protected_branches(p)

      cond do
        pushes_named_branch?(cmd, branches) -> true
        no_branch_arg?(cmd) -> current_branch_protected?(ctx, branches)
        true -> false
      end
    else
      false
    end
  end

  def matches?(_, _), do: false

  defp git_push?(cmd), do: Regex.match?(~r/\bgit\s+push\b/, cmd)

  defp pushes_named_branch?(cmd, branches) do
    Enum.any?(branches, fn b ->
      Regex.match?(~r/\bgit\s+push\b[^;&|]*\b#{Regex.escape(b)}\b/, cmd)
    end)
  end

  defp no_branch_arg?(cmd) do
    # git push with at most a remote (no explicit branch spec)
    Regex.match?(~r/\bgit\s+push(?:\s+--?\S+)*(?:\s+[A-Za-z0-9_.-]+)?\s*$/, String.trim(cmd))
  end

  defp current_branch_protected?(%Context{project_path: cwd}, branches) when is_binary(cwd) do
    case System.cmd("git", ["symbolic-ref", "--short", "HEAD"], cd: cwd, stderr_to_stdout: true) do
      {out, 0} -> String.trim(out) in branches
      _ -> false
    end
  rescue
    e in ErlangError ->
      Logger.warning(
        "BlockPushMaster: failed to determine current branch in #{cwd}: #{inspect(e)}"
      )

      false
  end

  defp current_branch_protected?(_, _), do: false

  defp protected_branches(%Policy{condition: %{} = cond}) do
    Map.get(cond, "protectedBranches") || Map.get(cond, :protectedBranches) || @default_branches
  end

  defp protected_branches(_), do: @default_branches
end
