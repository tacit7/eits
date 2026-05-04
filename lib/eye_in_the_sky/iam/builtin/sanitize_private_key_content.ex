defmodule EyeInTheSky.IAM.Builtin.SanitizePrivateKeyContent do
  @moduledoc """
  Warn when tool output contains PEM private key material.

  Detects the `-----BEGIN * PRIVATE KEY-----` header pattern that appears in
  RSA, EC, PKCS#8, and OpenSSH private keys. Key material in tool responses
  can leak credentials silently into logs, chat histories, or downstream tools.

  Effect: `instruct` (PostToolUse) — appends a warning; does not block.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @pem_re ~r/-----BEGIN [A-Z ]*PRIVATE KEY-----/

  @impl true
  def matches?(%Policy{} = _p, %Context{event: :post_tool_use, tool_response: resp})
      when is_binary(resp) do
    Regex.match?(@pem_re, resp)
  end

  def matches?(_, _), do: false
end
