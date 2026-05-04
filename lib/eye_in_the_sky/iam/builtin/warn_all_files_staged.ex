defmodule EyeInTheSky.IAM.Builtin.WarnAllFilesStaged do
  @moduledoc """
  Match (intended for `instruct` effect) Bash invocations of broad `git add`
  forms that stage everything: `git add .`, `git add -A`, `git add --all`,
  `git add -u`, `git add *`.

  Staging everything in the wrong directory (e.g. repo root when only a
  subdirectory was intended) is a common agent footgun — especially when
  `cwd` differs from the project root or when `.gitignore` is incomplete.

  The matcher fires a warning so the agent is prompted to verify the staged
  diff before committing. It does not block the operation.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  # Matches: git add ., git add -A, git add --all, git add -u, git add *
  # Anchored so "git add lib/" does not match.
  @broad_add_re ~r/\bgit\s+add\s+(?:\.|-A|--all|-u|\*)(?:\s|$)/

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@broad_add_re, cmd)
  end

  def matches?(_, _), do: false
end
