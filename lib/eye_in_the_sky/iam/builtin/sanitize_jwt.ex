defmodule EyeInTheSky.IAM.Builtin.SanitizeJwt do
  @moduledoc """
  Warn when tool output contains a JWT token (three base64url-encoded segments
  separated by dots, each at least 8 characters).

  Effect: `instruct` (PostToolUse) — appends a warning; does not block.

  JWTs in tool responses can leak session credentials, service account tokens,
  or signed payloads that should not be logged or forwarded.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  # Three base64url segments (min 8 chars each) separated by dots.
  # Minimum lengths avoid false-positives on version strings like "1.2.3".
  @jwt_re ~r/[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/

  @impl true
  def matches?(%Policy{} = _p, %Context{event: :post_tool_use, tool_response: resp})
      when is_binary(resp) do
    Regex.match?(@jwt_re, resp)
  end

  def matches?(_, _), do: false
end
