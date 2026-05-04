defmodule EyeInTheSky.IAM.Builtin.SanitizeJwtTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.SanitizeJwt
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp policy, do: %Policy{}

  defp post_ctx(resp),
    do: %Context{event: :post_tool_use, tool: "Bash", tool_response: resp}

  defp pre_ctx(cmd),
    do: %Context{event: :pre_tool_use, tool: "Bash", resource_content: cmd}

  # ── positive matches ────────────────────────────────────────────────────────

  test "matches a real JWT-like token in tool_response" do
    jwt = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    assert SanitizeJwt.matches?(policy(), post_ctx("token: #{jwt}"))
  end

  test "matches JWT embedded in JSON output" do
    body = ~s({"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMTIzNDU2Nzg5MCJ9.abc123defghijklmnopq","token_type":"Bearer"})
    assert SanitizeJwt.matches?(policy(), post_ctx(body))
  end

  # ── negative — false positive guards ────────────────────────────────────────

  test "does not match short dot-separated version strings like 1.2.3" do
    refute SanitizeJwt.matches?(policy(), post_ctx("mix 1.14.3 compiled ok"))
  end

  test "does not match segments shorter than 8 chars" do
    refute SanitizeJwt.matches?(policy(), post_ctx("short.val.xyz"))
  end

  test "does not match file paths with dots" do
    refute SanitizeJwt.matches?(policy(), post_ctx("lib/foo/bar.test.exs"))
  end

  # ── event / nil guards ──────────────────────────────────────────────────────

  test "does not match on PreToolUse event" do
    jwt = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf"
    refute SanitizeJwt.matches?(policy(), pre_ctx(jwt))
  end

  test "does not match when tool_response is nil" do
    refute SanitizeJwt.matches?(policy(), %Context{event: :post_tool_use, tool_response: nil})
  end

  test "does not match empty tool_response" do
    refute SanitizeJwt.matches?(policy(), post_ctx(""))
  end
end
