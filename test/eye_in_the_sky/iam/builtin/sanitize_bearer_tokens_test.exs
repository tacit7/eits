defmodule EyeInTheSky.IAM.Builtin.SanitizeBearerTokensTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.SanitizeBearerTokens
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp policy, do: %Policy{}
  defp post_ctx(resp), do: %Context{event: :post_tool_use, tool_response: resp}
  defp pre_ctx(cmd), do: %Context{event: :pre_tool_use, tool: "Bash", resource_content: cmd}

  # ── positive matches ────────────────────────────────────────────────────────

  test "matches Authorization: Bearer header with long token" do
    resp = "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9abc"
    assert SanitizeBearerTokens.matches?(policy(), post_ctx(resp))
  end

  test "matches lowercase bearer" do
    resp = "bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9abcdefghijk"
    assert SanitizeBearerTokens.matches?(policy(), post_ctx(resp))
  end

  test "matches mixed-case BEARER" do
    resp = "BEARER abcdefghijklmnopqrstuvwxyz1234567890"
    assert SanitizeBearerTokens.matches?(policy(), post_ctx(resp))
  end

  test "matches Bearer token embedded in JSON" do
    resp = ~s({"headers":{"Authorization":"Bearer sk-abcdefghijklmnopqrstuvwxyz"}})
    assert SanitizeBearerTokens.matches?(policy(), post_ctx(resp))
  end

  # ── negative — too-short token ───────────────────────────────────────────────

  test "does not match Bearer with short token (< 20 chars)" do
    refute SanitizeBearerTokens.matches?(policy(), post_ctx("Bearer tooshort"))
  end

  test "does not match Bearer with 19-char token" do
    refute SanitizeBearerTokens.matches?(policy(), post_ctx("Bearer 1234567890123456789"))
  end

  # ── event / nil guards ──────────────────────────────────────────────────────

  test "does not match on PreToolUse event" do
    refute SanitizeBearerTokens.matches?(policy(), pre_ctx("curl -H 'Bearer longtoken12345678901234'"))
  end

  test "does not match when tool_response is nil" do
    refute SanitizeBearerTokens.matches?(policy(), %Context{event: :post_tool_use, tool_response: nil})
  end

  test "does not match empty tool_response" do
    refute SanitizeBearerTokens.matches?(policy(), post_ctx(""))
  end
end
