defmodule EyeInTheSky.Redaction do
  @moduledoc """
  Shared secret-material redaction for user-visible text — flash messages,
  provider error messages, system chat entries, logs.

  ## Design tradeoff

  This module errs on the side of **over-redaction**. Legitimate long opaque
  identifiers (git SHAs, base64 nonces, opaque request ids) embedded in prose
  can be replaced with `[redacted]`. That is acceptable; under-redaction is
  not — leaking API key material into a flash message or persisted system
  message is a security regression this module exists to prevent.

  Patterns covered (case-sensitive unless noted):
    * generic `sk-...`, `sk_...`, `key-/key_...`, `token-/token_...` (case-insensitive)
    * Google API keys: `AIza[A-Za-z0-9_\\-]{30,}`
    * GitHub PATs: `gh[pousr]_[A-Za-z0-9]{20,}` and `github_pat_[A-Za-z0-9_]{20,}`
    * Groq: `gsk_[A-Za-z0-9]{20,}`
    * OpenRouter: `sk-or-[A-Za-z0-9\\-]{20,}`
    * Generic long bearer-ish blobs: a run of 32+ base64url/underscore chars
      following a `:`, `=`, or whitespace boundary (the "over-redaction"
      backstop for unknown provider formats)

  Order matters — provider-specific patterns run before the generic prefix
  rule so their labels (`sk-or-`, `gh[pousr]_`) get consumed as part of the
  match instead of being partially left behind.
  """

  # Provider-specific patterns run first so they consume distinctive prefixes
  # (sk-or-, gh[pousr]_, github_pat_, gsk_, AIza) whole. The generic prefix
  # rule (sk|key|token) then catches everything else with those roots, and
  # the long-blob backstop mops up the rest.
  @patterns [
    # OpenRouter must precede the generic sk|key|token rule so "sk-or-" isn't
    # eaten by the shorter prefix.
    ~r/sk-or-[A-Za-z0-9\-]{20,}/,
    # GitHub personal access tokens (fine-grained and classic)
    ~r/github_pat_[A-Za-z0-9_]{20,}/,
    ~r/gh[pousr]_[A-Za-z0-9]{20,}/,
    # Groq
    ~r/gsk_[A-Za-z0-9]{20,}/,
    # Google API keys
    ~r/AIza[A-Za-z0-9_\-]{30,}/,
    # Generic sk/key/token prefixes (preserves the historical pattern; case-insensitive)
    ~r/\b(sk|key|token)[-_][A-Za-z0-9_\-]{8,}\b/i,
    # Long opaque bearer-ish blob following a boundary character.
    # Uses a non-capturing lookbehind alternative by matching+dropping the
    # boundary char; then the run of chars, then a whitespace/quote/EOL guard.
    ~r/(?<=[:=\s])[A-Za-z0-9_\-]{32,}(?=[\s"']|$)/
  ]

  @redacted "[redacted]"

  @doc """
  Redact known and suspected key material from `text`.

  Returns the input unchanged for `nil` and non-binaries (callers can pass
  arbitrary error tuples after inspect/1; the caller is responsible for
  stringifying first if they want redaction).
  """
  @spec redact(term()) :: term()
  def redact(text) when is_binary(text) do
    Enum.reduce(@patterns, text, fn pattern, acc ->
      Regex.replace(pattern, acc, @redacted)
    end)
  end

  def redact(other), do: other

  @doc """
  Inspect an arbitrary term and redact the result. Intended for turning
  opaque `{:error, reason}` tuples into user-safe short strings when the
  reason may have transitively captured submitted key material (e.g. Task
  crash reports or provider echo-back error messages).
  """
  @spec redact_inspect(term(), keyword()) :: String.t()
  def redact_inspect(term, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    term
    |> inspect(limit: :infinity, printable_limit: :infinity)
    |> redact()
    |> String.slice(0, limit)
  end
end
