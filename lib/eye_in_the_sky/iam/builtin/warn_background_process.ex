defmodule EyeInTheSky.IAM.Builtin.WarnBackgroundProcess do
  @moduledoc """
  Match (intended for `instruct` effect) Bash commands that background a
  process with `&` or `nohup ... &`.

  Agents that background processes cannot reliably track or clean them up.
  The process may outlive the session, consume resources, or leave ports
  bound after the agent exits.

  Does not fire on `&&` (logical AND) — only on trailing `&` or `& ` used
  as a background operator.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  # Matches & at end of command or & followed by whitespace/disown/wait,
  # but not && (logical AND).
  @bg_re ~r/(?<!\&)\&(?!\&)(?:\s|$)/

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@bg_re, cmd)
  end

  def matches?(_, _), do: false
end
