defmodule EyeInTheSky.IAM.Builtin.WarnGitStashDrop do
  @moduledoc """
  Match (intended for `instruct` effect) Bash invocations of
  `git stash drop` or `git stash clear`.

  Both operations permanently discard stashed changes with no recovery path
  (unless the stash ref is still in the reflog). Agents sometimes drop
  stashes after popping them, unaware that the pop failed or that the stash
  contained unrelated work.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @drop_re ~r/\bgit\s+stash\s+(?:drop|clear)\b/

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@drop_re, cmd)
  end

  def matches?(_, _), do: false
end
