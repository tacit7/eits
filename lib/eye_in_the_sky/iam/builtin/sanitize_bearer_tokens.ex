defmodule EyeInTheSky.IAM.Builtin.SanitizeBearerTokens do
  @moduledoc """
  Warn when tool output contains an HTTP Authorization Bearer token.

  Matches `Bearer <token>` patterns (case-insensitive) where the token is at
  least 20 characters — long enough to be a real credential, short enough to
  avoid false-positives on placeholder strings.

  Effect: `instruct` (PostToolUse) — appends a warning; does not block.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @bearer_re ~r/\bBearer\s+[A-Za-z0-9\-._~+\/]{20,}/i

  @impl true
  def matches?(%Policy{} = _p, %Context{event: :post_tool_use, tool_response: resp})
      when is_binary(resp) do
    Regex.match?(@bearer_re, resp)
  end

  def matches?(_, _), do: false
end
