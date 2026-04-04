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
      assert ErrorClassifier.systemic?(
               {:claude_result_error, %{errors: "authentication_error"}}
             )
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
end
