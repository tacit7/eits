defmodule EyeInTheSky.IAM.HookResponseTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Decision
  alias EyeInTheSky.IAM.HookResponse
  alias EyeInTheSky.IAM.Policy

  defp policy(attrs \\ []) do
    base = %Policy{
      id: 1,
      name: "test-policy",
      system_key: nil,
      effect: "allow",
      agent_type: "*",
      action: "*",
      priority: 0,
      enabled: true,
      message: "test message",
      condition: %{},
      editable_fields: []
    }

    struct(base, attrs)
  end

  defp decision(attrs \\ []) do
    base = %Decision{
      permission: :allow,
      winning_policy: nil,
      reason: nil,
      instructions: [],
      default?: false,
      evaluated_count: 1
    }

    struct(base, attrs)
  end

  # ── deny × PreToolUse ───────────────────────────────────────────────────────

  describe "deny + :pre_tool_use" do
    test "uses permissionDecision deny with reason" do
      p = policy(effect: "deny", message: "rm -rf blocked")
      d = decision(permission: :deny, winning_policy: p, reason: "rm -rf blocked")

      result = HookResponse.from_decision(d, :pre_tool_use)

      assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
      assert result["hookSpecificOutput"]["hookEventName"] == "PreToolUse"
      assert result["hookSpecificOutput"]["permissionDecisionReason"] == "rm -rf blocked"
      refute Map.has_key?(result, "continue")
    end

    test "falls back to default reason when reason is nil" do
      d = decision(permission: :deny, reason: nil)
      result = HookResponse.from_decision(d, :pre_tool_use)
      assert result["hookSpecificOutput"]["permissionDecisionReason"] =~ "Denied"
    end
  end

  # ── deny × non-PreToolUse ───────────────────────────────────────────────────

  describe "deny + :post_tool_use" do
    test "uses continue: false with stopReason" do
      d = decision(permission: :deny, reason: "blocked post-tool")
      result = HookResponse.from_decision(d, :post_tool_use)

      assert result["continue"] == false
      assert result["stopReason"] == "blocked post-tool"
      refute Map.has_key?(result, "hookSpecificOutput")
    end
  end

  describe "deny + :stop" do
    test "uses continue: false" do
      d = decision(permission: :deny, reason: "stop denied")
      result = HookResponse.from_decision(d, :stop)

      assert result["continue"] == false
      assert result["stopReason"] == "stop denied"
    end
  end

  # ── allow, no instructions × PreToolUse ────────────────────────────────────

  describe "allow + no instructions + :pre_tool_use" do
    test "returns continue: true with permissionDecision allow" do
      d = decision(permission: :allow, instructions: [])
      result = HookResponse.from_decision(d, :pre_tool_use)

      assert result["continue"] == true
      assert result["hookSpecificOutput"]["permissionDecision"] == "allow"
      assert result["hookSpecificOutput"]["hookEventName"] == "PreToolUse"
      refute Map.has_key?(result["hookSpecificOutput"], "additionalContext")
    end
  end

  # ── allow, with instructions × PreToolUse ──────────────────────────────────

  describe "allow + instructions + :pre_tool_use" do
    test "includes additionalContext with rendered instructions" do
      p1 = policy(name: "security-policy", message: "use safe rm")
      p2 = policy(id: 2, name: "audit-policy", message: "log all writes")

      d =
        decision(
          permission: :allow,
          instructions: [
            %{policy: p1, message: "use safe rm"},
            %{policy: p2, message: "log all writes"}
          ]
        )

      result = HookResponse.from_decision(d, :pre_tool_use)

      assert result["continue"] == true
      assert result["hookSpecificOutput"]["permissionDecision"] == "allow"
      ctx = result["hookSpecificOutput"]["additionalContext"]
      assert ctx =~ "security-policy"
      assert ctx =~ "use safe rm"
      assert ctx =~ "audit-policy"
      assert ctx =~ "log all writes"
    end
  end

  # ── allow, no instructions × non-PreToolUse ────────────────────────────────

  describe "allow + no instructions + :post_tool_use" do
    test "returns minimal continue: true" do
      d = decision(permission: :allow, instructions: [])
      result = HookResponse.from_decision(d, :post_tool_use)

      assert result == %{"continue" => true}
    end
  end

  describe "allow + no instructions + :stop" do
    test "returns minimal continue: true" do
      d = decision(permission: :allow, instructions: [])
      result = HookResponse.from_decision(d, :stop)

      assert result == %{"continue" => true}
    end
  end

  # ── allow, with instructions × non-PreToolUse ──────────────────────────────

  describe "allow + instructions + :post_tool_use" do
    test "returns suppressOutput with additionalContext" do
      p = policy(name: "instruct-policy", message: "be careful")
      d = decision(permission: :allow, instructions: [%{policy: p, message: "be careful"}])

      result = HookResponse.from_decision(d, :post_tool_use)

      assert result["continue"] == true
      assert result["suppressOutput"] == true
      assert result["hookSpecificOutput"]["hookEventName"] == "PostToolUse"
      assert result["hookSpecificOutput"]["additionalContext"] =~ "instruct-policy"
    end
  end

  describe "allow + instructions + :stop" do
    test "returns suppressOutput with Stop hookEventName" do
      p = policy(name: "stop-instruct", message: "log stop event")
      d = decision(permission: :allow, instructions: [%{policy: p, message: "log stop event"}])

      result = HookResponse.from_decision(d, :stop)

      assert result["hookSpecificOutput"]["hookEventName"] == "Stop"
    end
  end
end
