defmodule EyeInTheSky.IAM.Builtin.SanitizeApiKeys do
  @moduledoc """
  Detects and redacts API keys, access tokens, and credentials in PostToolUse
  tool output.

  Redaction labels:
    * `sk-ant-*`         → `[REDACTED:anthropic]`
    * `sk-*`             → `[REDACTED:openai]`
    * `ghp_/gho_/ghs_/ghu_` → `[REDACTED:github]`
    * `AKIA*`            → `[REDACTED:aws]`
    * generic key=value  → `[REDACTED:generic]`
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @patterns [
    {~r/sk-ant-[a-zA-Z0-9\-_]{20,}/, "anthropic"},
    {~r/sk-[a-zA-Z0-9]{20,}/, "openai"},
    {~r/gh[posu]_[a-zA-Z0-9_]{36,}/, "github"},
    {~r/AKIA[0-9A-Z]{16}/, "aws"},
    {~r/(?i)(api[_-]?key|secret|token|password)\s*[=:]\s*['"]?[^\s'"]{12,}['"]?/, "generic"}
  ]

  @impl true
  def matches?(%Policy{}, %Context{tool_response: response}) when is_binary(response) do
    has_secret?(response)
  end

  def matches?(_, _), do: false

  @impl true
  def instruction_message(%Policy{}, %Context{tool_response: response})
      when is_binary(response) do
    {sanitized, _count, summary} = redact(response)
    "#{summary}\n\n#{sanitized}"
  end

  def instruction_message(_, _), do: nil

  @doc """
  Redact secrets from the given text. Returns `{sanitized, count, summary}`.
  `summary` is nil when nothing was redacted.
  """
  @spec redact(String.t()) :: {String.t(), non_neg_integer(), String.t() | nil}
  def redact(text) when is_binary(text) do
    {redacted, count, kinds} =
      Enum.reduce(@patterns, {text, 0, []}, fn {re, kind}, {acc, n, ks} ->
        hits = Regex.scan(re, acc)

        if hits == [] do
          {acc, n, ks}
        else
          {String.replace(acc, re, "[REDACTED:#{kind}]"), n + length(hits),
           ks ++ ["#{kind} (#{length(hits)})"]}
        end
      end)

    summary = if kinds == [], do: nil, else: "Redacted: #{Enum.join(kinds, ", ")}"
    {redacted, count, summary}
  end

  defp has_secret?(text), do: Enum.any?(@patterns, fn {re, _} -> Regex.match?(re, text) end)
end
