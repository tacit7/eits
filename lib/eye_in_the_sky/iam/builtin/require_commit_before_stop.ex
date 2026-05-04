defmodule EyeInTheSky.IAM.Builtin.RequireCommitBeforeStop do
  @moduledoc """
  Warn when a session ends with uncommitted changes in the working tree.

  Effect: `instruct` (Stop event) — injects a warning into the session
  transcript before Claude Code shuts down so the user is reminded to
  commit (or at least review) outstanding work.

  Runs `git status --porcelain` against `ctx.project_path` (the CWD that
  Claude Code reported when the Stop hook fired). A non-empty result means
  staged, unstaged, or untracked files are present.

  ## Condition keys

  - `"checkUntracked"` (`boolean`, default `true`) — when `false`, untracked
    files (`?? …`) are ignored; only staged/unstaged changes trigger the warn.
  - `"ignorePaths"` (`[string]`, default `[]`) — list of path prefixes to
    exclude from the check (e.g. `["_build", "deps", ".elixir_ls"]`).

  ## Notes

  - If `project_path` is nil, or if `git status` exits non-zero (not a git
    repo), the matcher returns `false` — no false positives for non-git dirs.
  - Only fires on the `Stop` event; no-op for all other hook events.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @impl true
  def matches?(%Policy{} = p, %Context{event: :stop, project_path: cwd})
      when is_binary(cwd) do
    case git_status(cwd) do
      {:ok, lines} ->
        lines
        |> filter_untracked(p)
        |> filter_ignored_paths(p)
        |> Enum.any?()

      :error ->
        false
    end
  end

  def matches?(_, _), do: false

  # ── git status ───────────────────────────────────────────────────────────────

  defp git_status(cwd) do
    case System.cmd("git", ["-C", cwd, "status", "--porcelain", "--ignore-submodules"],
           stderr_to_stdout: false
         ) do
      {output, 0} ->
        lines =
          output
          |> String.split("\n", trim: true)

        {:ok, lines}

      _ ->
        :error
    end
  end

  # ── filters ──────────────────────────────────────────────────────────────────

  # Drop untracked lines ("?? path") when checkUntracked is false.
  defp filter_untracked(lines, %Policy{condition: cond}) do
    check_untracked = get_condition(cond, "checkUntracked", true)

    if check_untracked do
      lines
    else
      Enum.reject(lines, &String.starts_with?(&1, "??"))
    end
  end

  # Drop lines whose path starts with any of the ignorePaths prefixes.
  defp filter_ignored_paths(lines, %Policy{condition: cond}) do
    ignored = get_condition(cond, "ignorePaths", [])

    if ignored == [] do
      lines
    else
      Enum.reject(lines, fn line ->
        # porcelain format: "XY path" or "XY old -> new"
        path = line |> String.slice(3..-1//1) |> String.split(" -> ") |> List.first("")
        Enum.any?(ignored, &String.starts_with?(path, &1))
      end)
    end
  end

  defp get_condition(nil, _key, default), do: default
  defp get_condition(cond, key, default) when is_map(cond), do: Map.get(cond, key, default)
end
