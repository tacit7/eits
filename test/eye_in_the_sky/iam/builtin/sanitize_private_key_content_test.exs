defmodule EyeInTheSky.IAM.Builtin.SanitizePrivateKeyContentTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.SanitizePrivateKeyContent
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp policy, do: %Policy{}
  defp post_ctx(resp), do: %Context{event: :post_tool_use, tool_response: resp}
  defp pre_ctx(cmd), do: %Context{event: :pre_tool_use, tool: "Bash", resource_content: cmd}

  # ── positive matches ────────────────────────────────────────────────────────

  test "matches RSA private key header" do
    assert SanitizePrivateKeyContent.matches?(policy(), post_ctx("-----BEGIN RSA PRIVATE KEY-----\nMIIE..."))
  end

  test "matches PKCS8 private key header" do
    assert SanitizePrivateKeyContent.matches?(policy(), post_ctx("-----BEGIN PRIVATE KEY-----\nMIIE..."))
  end

  test "matches EC private key header" do
    assert SanitizePrivateKeyContent.matches?(policy(), post_ctx("-----BEGIN EC PRIVATE KEY-----\nMHQC..."))
  end

  test "matches OpenSSH private key header" do
    assert SanitizePrivateKeyContent.matches?(policy(), post_ctx("-----BEGIN OPENSSH PRIVATE KEY-----\nb3Bl..."))
  end

  test "matches key embedded in larger output" do
    resp = "file contents:\n-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA...\n-----END RSA PRIVATE KEY-----"
    assert SanitizePrivateKeyContent.matches?(policy(), post_ctx(resp))
  end

  # ── negative ─────────────────────────────────────────────────────────────────

  test "does not match public key" do
    refute SanitizePrivateKeyContent.matches?(policy(), post_ctx("-----BEGIN PUBLIC KEY-----\nMIIBIjAN..."))
  end

  test "does not match certificate" do
    refute SanitizePrivateKeyContent.matches?(policy(), post_ctx("-----BEGIN CERTIFICATE-----\nMIID..."))
  end

  test "does not match arbitrary PEM-like text without PRIVATE KEY" do
    refute SanitizePrivateKeyContent.matches?(policy(), post_ctx("-----BEGIN DH PARAMETERS-----\nMIIB..."))
  end

  # ── event / nil guards ──────────────────────────────────────────────────────

  test "does not match on PreToolUse event" do
    refute SanitizePrivateKeyContent.matches?(policy(), pre_ctx("cat id_rsa"))
  end

  test "does not match when tool_response is nil" do
    refute SanitizePrivateKeyContent.matches?(policy(), %Context{event: :post_tool_use, tool_response: nil})
  end
end
