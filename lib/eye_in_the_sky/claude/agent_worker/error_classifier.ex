defmodule EyeInTheSky.Claude.AgentWorker.ErrorClassifier do
  @moduledoc """
  Classifies SDK error reasons for retry decisions and UI display.

  `classify/1` is the single source of truth: it maps a reason term to a
  category atom (`:billing_error`, `:authentication_error`, `:rate_limit_error`,
  `:watchdog_timeout`, `:retry_exhausted`, `:transient`).

  `systemic?/1` derives from `classify/1` — anything other than `:transient`
  is systemic and should not be retried.

  `status_reason/1` returns the string value persisted to
  `sessions.status_reason` so the LiveView badge layer can distinguish a
  billing failure from a generic crash.
  """

  # Pattern-match on actual error term shapes rather than inspect() strings.
  # Parser emits {:billing_error, msg} / {:authentication_error, msg} as atoms.
  # Unknown errors and result errors carry free-form strings that still need
  # substring matching, but only within the message field — not on inspect output.

  @type category ::
          :billing_error
          | :authentication_error
          | :rate_limit_error
          | :watchdog_timeout
          | :retry_exhausted
          | :user_canceled
          | :model_not_found
          | :transient

  # Rate-limit (429) is CATEGORIZED so the UI can surface a distinct badge, but
  # NOT SYSTEMIC — the worker retries with exponential backoff (see
  # RetryPolicy, commit 21bafe38 which tuned the 429 backoff ceiling + jitter).
  # Failing fast on the first 429 would regress Max-plan users who routinely
  # hit short-lived burst throttling.
  @non_systemic_categories [:transient, :rate_limit_error]

  @spec systemic?(term()) :: boolean()
  def systemic?(reason), do: classify(reason) not in @non_systemic_categories

  @doc """
  Map a reason term to a category atom. Unknown or retryable reasons return
  `:transient`.
  """
  @spec classify(term()) :: category()
  def classify({:watchdog_timeout, _timeout_ms}), do: :watchdog_timeout
  def classify({:billing_error, _}), do: :billing_error
  def classify({:authentication_error, _}), do: :authentication_error
  def classify({:rate_limit_error, _}), do: :rate_limit_error
  def classify(:retry_exhausted), do: :retry_exhausted
  # User-initiated cancel — terminal, MUST NOT be retried (spec invariant:
  # canceled turns are never re-run). Emitted by Pi.SDK when a cancel is
  # observed on any terminal path (turn_end, clean exit, abnormal exit).
  def classify(:user_canceled), do: :user_canceled

  # Pi harness renders provider errors as markdown text — classify by content.
  # Order matters: billing before auth (a 400 usage error must not read as generic).
  def classify({:pi_turn_error, msg}) when is_binary(msg) do
    cond do
      msg =~ ~r/out of .*usage|quota|credit|billing/iu -> :billing_error
      msg =~ ~r/HTTP 429|rate.?limit|overloaded/iu -> :rate_limit_error
      msg =~ ~r/HTTP 40[13]|authentication|invalid[ _]?(api[ _-]?key|x-api-key|token)/iu -> :authentication_error
      msg =~ ~r/HTTP 404|not_found_error|unknown model/iu -> :model_not_found
      true -> :transient
    end
  end

  def classify({:pi_turn_error, _}), do: :transient

  # errors is a list of strings — scan each entry
  def classify({:claude_result_error, %{errors: errors}}) when is_list(errors) do
    cond do
      Enum.any?(errors, &String.contains?(&1, "billing_error")) -> :billing_error
      Enum.any?(errors, &String.contains?(&1, "authentication_error")) -> :authentication_error
      Enum.any?(errors, &String.contains?(&1, "rate_limit_error")) -> :rate_limit_error
      true -> :transient
    end
  end

  # errors is a map — parser sets this from event["error"] object e.g. %{"type" => "billing_error"}
  def classify({:claude_result_error, %{errors: %{"type" => "billing_error"}}}),
    do: :billing_error

  def classify({:claude_result_error, %{errors: %{"type" => "authentication_error"}}}),
    do: :authentication_error

  def classify({:claude_result_error, %{errors: %{"type" => "rate_limit_error"}}}),
    do: :rate_limit_error

  # errors is a raw string — check for known systemic markers
  def classify({:claude_result_error, %{errors: errors}}) when is_binary(errors) do
    cond do
      String.contains?(errors, "billing_error") -> :billing_error
      String.contains?(errors, "authentication_error") -> :authentication_error
      String.contains?(errors, "rate_limit_error") -> :rate_limit_error
      true -> :transient
    end
  end

  # fallback: check the result text for billing messages when errors field is absent/nil
  def classify({:claude_result_error, %{result: result}}) when is_binary(result) do
    if String.contains?(result, ["Credit balance is too low", "missing binary"]),
      do: :billing_error,
      else: :transient
  end

  def classify({:unknown_error, msg}) when is_binary(msg) do
    if String.contains?(msg, ["Credit balance is too low", "missing binary"]),
      do: :billing_error,
      else: :transient
  end

  def classify(_), do: :transient

  @doc """
  Category string persisted to `sessions.status_reason`. Returns `nil` for
  transient reasons so a recoverable hiccup does not overwrite a prior
  terminal reason.
  """
  @spec status_reason(term()) :: String.t() | nil
  def status_reason(reason) do
    case classify(reason) do
      :transient -> nil
      category -> Atom.to_string(category)
    end
  end
end
