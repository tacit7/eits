defmodule EyeInTheSky.IAM.Builtin.WarnGitAmend do
  @moduledoc """
  Match (intended for `instruct` effect) Bash invocations of
  `git commit --amend` or `git rebase -i` / `git rebase --interactive`.

  Both operations rewrite history. Amending a commit that has already been
  pushed silently diverges the remote, requiring a force-push to recover.
  Interactive rebase on a shared branch has the same effect.

  This matcher fires on `PreToolUse` so the agent receives a warning before
  executing, not after.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  # git commit --amend (with or without --no-edit, --message, etc.)
  @amend_re ~r/\bgit\s+commit\b.*\s--amend\b/

  # git rebase -i / --interactive
  @rebase_interactive_re ~r/\bgit\s+rebase\b.*\s(?:-i|--interactive)\b/

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@amend_re, cmd) or Regex.match?(@rebase_interactive_re, cmd)
  end

  def matches?(_, _), do: false
end
