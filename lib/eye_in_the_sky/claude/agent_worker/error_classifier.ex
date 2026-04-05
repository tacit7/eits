defmodule EyeInTheSky.Claude.AgentWorker.ErrorClassifier do
  @moduledoc """
  Classifies SDK error reasons as systemic (non-retryable) or transient (retryable).

  Systemic errors — billing failures, authentication errors, missing binary — should
  not be retried. All other errors are considered transient and eligible for retry.
  """

  # Pattern-match on actual error term shapes rather than inspect() strings.
  # Parser emits {:billing_error, msg} / {:authentication_error, msg} as atoms.
  # Unknown errors and result errors carry free-form strings that still need
  # substring matching, but only within the message field — not on inspect output.

  @spec systemic?(term()) :: boolean()
  def systemic?({:watchdog_timeout, _timeout_ms}), do: true
  def systemic?({:billing_error, _}), do: true
  def systemic?({:authentication_error, _}), do: true

  # errors is a list of strings — scan each entry
  def systemic?({:claude_result_error, %{errors: errors}}) when is_list(errors) do
    Enum.any?(errors, &String.contains?(&1, ["billing_error", "authentication_error"]))
  end

  # errors is a map — parser sets this from event["error"] object e.g. %{"type" => "billing_error"}
  def systemic?({:claude_result_error, %{errors: %{"type" => type}}})
      when type in ["billing_error", "authentication_error"],
      do: true

  # errors is a raw string — check for known systemic markers
  def systemic?({:claude_result_error, %{errors: errors}}) when is_binary(errors) do
    String.contains?(errors, ["billing_error", "authentication_error"])
  end

  # fallback: check the result text for billing messages when errors field is absent/nil
  def systemic?({:claude_result_error, %{result: result}}) when is_binary(result) do
    String.contains?(result, ["Credit balance is too low", "missing binary"])
  end

  def systemic?({:unknown_error, msg}) when is_binary(msg) do
    String.contains?(msg, ["Credit balance is too low", "missing binary"])
  end

  def systemic?(_), do: false
end
