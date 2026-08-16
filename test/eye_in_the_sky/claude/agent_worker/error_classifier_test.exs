defmodule EyeInTheSky.Claude.AgentWorker.ErrorClassifierTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.AgentWorker.ErrorClassifier

  describe "systemic?/1 — atom-tagged billing/auth errors" do
    test "billing_error tuple is systemic" do
      assert ErrorClassifier.systemic?({:billing_error, "Credit balance is too low"})
    end

    test "billing_error with any message is systemic" do
      assert ErrorClassifier.systemic?({:billing_error, "some other billing msg"})
    end

    test "authentication_error tuple is systemic" do
      assert ErrorClassifier.systemic?({:authentication_error, "invalid token"})
    end
  end

  describe "systemic?/1 — claude_result_error with errors list" do
    test "list containing billing_error string is systemic" do
      assert ErrorClassifier.systemic?(
               {:claude_result_error, %{errors: ["billing_error occurred"]}}
             )
    end

    test "list containing authentication_error string is systemic" do
      assert ErrorClassifier.systemic?(
               {:claude_result_error, %{errors: ["authentication_error: token expired"]}}
             )
    end

    test "list with no systemic markers is not systemic" do
      refute ErrorClassifier.systemic?(
               {:claude_result_error, %{errors: ["timeout", "connection reset"]}}
             )
    end

    test "empty list is not systemic" do
      refute ErrorClassifier.systemic?({:claude_result_error, %{errors: []}})
    end
  end

  describe "systemic?/1 — claude_result_error with errors map" do
    test "errors map with type billing_error is systemic" do
      assert ErrorClassifier.systemic?(
               {:claude_result_error, %{errors: %{"type" => "billing_error"}}}
             )
    end

    test "errors map with type authentication_error is systemic" do
      assert ErrorClassifier.systemic?(
               {:claude_result_error, %{errors: %{"type" => "authentication_error"}}}
             )
    end

    test "errors map with other type is not systemic" do
      refute ErrorClassifier.systemic?(
               {:claude_result_error, %{errors: %{"type" => "rate_limit"}}}
             )
    end
  end

  describe "systemic?/1 — claude_result_error with errors binary string" do
    test "binary containing billing_error is systemic" do
      assert ErrorClassifier.systemic?(
               {:claude_result_error, %{errors: "billing_error: quota exceeded"}}
             )
    end

    test "binary containing authentication_error is systemic" do
      assert ErrorClassifier.systemic?({:claude_result_error, %{errors: "authentication_error"}})
    end

    test "binary without systemic markers is not systemic" do
      refute ErrorClassifier.systemic?(
               {:claude_result_error, %{errors: "some transient network error"}}
             )
    end
  end

  describe "systemic?/1 — claude_result_error with result fallback" do
    test "result containing 'Credit balance is too low' is systemic" do
      assert ErrorClassifier.systemic?(
               {:claude_result_error, %{result: "Credit balance is too low"}}
             )
    end

    test "result containing 'missing binary' is systemic" do
      assert ErrorClassifier.systemic?(
               {:claude_result_error, %{result: "Error: missing binary in PATH"}}
             )
    end

    test "result without systemic markers is not systemic" do
      refute ErrorClassifier.systemic?(
               {:claude_result_error, %{result: "some unexpected output"}}
             )
    end
  end

  describe "systemic?/1 — unknown_error" do
    test "unknown_error with 'Credit balance is too low' is systemic" do
      assert ErrorClassifier.systemic?({:unknown_error, "Credit balance is too low"})
    end

    test "unknown_error with 'missing binary' is systemic" do
      assert ErrorClassifier.systemic?({:unknown_error, "missing binary: claude not found"})
    end

    test "unknown_error with generic message is not systemic" do
      refute ErrorClassifier.systemic?({:unknown_error, "process exited with code 1"})
    end
  end

  describe "systemic?/1 — catch-all" do
    test "unrecognized tuple is not systemic" do
      refute ErrorClassifier.systemic?({:some_other_error, "whatever"})
    end

    test "plain atom is not systemic" do
      refute ErrorClassifier.systemic?(:timeout)
    end

    test "nil is not systemic" do
      refute ErrorClassifier.systemic?(nil)
    end

    test "binary is not systemic" do
      refute ErrorClassifier.systemic?("Credit balance is too low")
    end
  end

  describe "classify/1" do
    test "billing_error tuple classifies as :billing_error" do
      assert ErrorClassifier.classify({:billing_error, "low balance"}) == :billing_error
    end

    test "authentication_error tuple classifies as :authentication_error" do
      assert ErrorClassifier.classify({:authentication_error, "bad token"}) ==
               :authentication_error
    end

    test "rate_limit_error tuple classifies as :rate_limit_error" do
      assert ErrorClassifier.classify({:rate_limit_error, "429"}) == :rate_limit_error
    end

    test "watchdog_timeout classifies as :watchdog_timeout" do
      assert ErrorClassifier.classify({:watchdog_timeout, 30_000}) == :watchdog_timeout
    end

    test ":retry_exhausted classifies as :retry_exhausted" do
      assert ErrorClassifier.classify(:retry_exhausted) == :retry_exhausted
    end

    test "claude_result_error errors list with rate_limit_error classifies as :rate_limit_error" do
      assert ErrorClassifier.classify(
               {:claude_result_error, %{errors: ["rate_limit_error: slow down"]}}
             ) == :rate_limit_error
    end

    test "claude_result_error errors map with type rate_limit_error classifies as :rate_limit_error" do
      assert ErrorClassifier.classify(
               {:claude_result_error, %{errors: %{"type" => "rate_limit_error"}}}
             ) == :rate_limit_error
    end

    test "generic/unknown reasons classify as :transient" do
      assert ErrorClassifier.classify({:some_other_error, "whatever"}) == :transient
      assert ErrorClassifier.classify(:timeout) == :transient
      assert ErrorClassifier.classify(nil) == :transient
    end

    test ":user_canceled classifies as :user_canceled (systemic — no retry)" do
      # Spec invariant: user-initiated cancels are terminal and MUST NOT be
      # re-run. Emitted by Pi.SDK on every terminal path (turn_end after cancel,
      # clean exit after cancel, abnormal exit after cancel).
      assert ErrorClassifier.classify(:user_canceled) == :user_canceled
      assert ErrorClassifier.systemic?(:user_canceled)
      assert ErrorClassifier.status_reason(:user_canceled) == "user_canceled"
    end

    test "rate_limit_error is NOT systemic — retries with backoff are preserved" do
      # 429s are transient by protocol (burst throttling clears in seconds).
      # Categorized so the UI can distinguish but NOT systemic so RetryPolicy
      # keeps its exponential-backoff retry loop.
      refute ErrorClassifier.systemic?({:rate_limit_error, "429"})
    end
  end

  describe "pi_turn_error content mapping" do
    test "usage/quota/billing -> :billing_error (systemic)" do
      for msg <- [
            "**Error · HTTP 400**\n\nYou're out of extra usage. Add more at claude.ai/settings/usage.\n\n_invalid_request_error_",
            "insufficient quota for this request",
            "credit balance is too low"
          ] do
        assert ErrorClassifier.classify({:pi_turn_error, msg}) == :billing_error
        assert ErrorClassifier.systemic?({:pi_turn_error, msg})
      end
    end

    test "auth -> :authentication_error" do
      for msg <- [
            "HTTP 401 authentication_error",
            "invalid api key provided",
            "HTTP 403 forbidden"
          ] do
        assert ErrorClassifier.classify({:pi_turn_error, msg}) == :authentication_error
      end
    end

    test "rate limit -> :rate_limit_error (retryable)" do
      for msg <- ["HTTP 429 rate_limit_error", "Rate limit exceeded", "overloaded_error"] do
        assert ErrorClassifier.classify({:pi_turn_error, msg}) == :rate_limit_error
        refute ErrorClassifier.systemic?({:pi_turn_error, msg})
      end
    end

    test "model 404 -> :model_not_found (systemic, no retry)" do
      msg = "**Error · HTTP 404**\n\nmodel: claude-3-5-haiku-20241022\n\n_not_found_error_"
      assert ErrorClassifier.classify({:pi_turn_error, msg}) == :model_not_found
      assert ErrorClassifier.systemic?({:pi_turn_error, msg})
      assert ErrorClassifier.status_reason({:pi_turn_error, msg}) == "model_not_found"
    end

    test "unrecognized pi error -> :transient" do
      assert ErrorClassifier.classify({:pi_turn_error, "connection reset by peer"}) == :transient
    end
  end

  describe "status_reason/1" do
    test "billing_error returns \"billing_error\" string" do
      assert ErrorClassifier.status_reason({:billing_error, "low"}) == "billing_error"
    end

    test "rate_limit_error returns \"rate_limit_error\" string" do
      assert ErrorClassifier.status_reason({:rate_limit_error, "429"}) == "rate_limit_error"
    end

    test "watchdog_timeout returns \"watchdog_timeout\" string" do
      assert ErrorClassifier.status_reason({:watchdog_timeout, 30_000}) == "watchdog_timeout"
    end

    test ":retry_exhausted returns \"retry_exhausted\" string" do
      assert ErrorClassifier.status_reason(:retry_exhausted) == "retry_exhausted"
    end

    test "transient reasons return nil so they don't clobber prior reasons" do
      assert ErrorClassifier.status_reason({:some_other_error, "x"}) == nil
      assert ErrorClassifier.status_reason(nil) == nil
    end
  end
end
