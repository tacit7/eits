defmodule EyeInTheSky.IAM.Builtin.BlockSecretsWriteTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockSecretsWrite
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(tool, path), do: %Context{tool: tool, resource_path: path}
  defp policy(cond \\ nil), do: %Policy{condition: cond}

  # ── extension matching ──────────────────────────────────────────────────────

  test "blocks Write to .pem file" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/certs/server.pem"))
  end

  test "blocks Write to .key file" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/certs/server.key"))
  end

  test "blocks Write to .pfx file" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/certs/cert.pfx"))
  end

  test "blocks Write to .p12 file" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/certs/cert.p12"))
  end

  test "blocks Write to .crt file" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/certs/server.crt"))
  end

  test "blocks Write to .cer file" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/certs/server.cer"))
  end

  # ── named key files ─────────────────────────────────────────────────────────

  test "blocks Write to id_rsa" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/home/user/.ssh/id_rsa"))
  end

  test "blocks Write to id_ed25519" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/home/user/.ssh/id_ed25519"))
  end

  test "blocks Write to id_ecdsa" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/home/user/.ssh/id_ecdsa"))
  end

  test "blocks Write to id_rsa.pub" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/home/user/.ssh/id_rsa.pub"))
  end

  # ── .ssh directory ──────────────────────────────────────────────────────────

  test "blocks Write to any file in ~/.ssh/" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/home/user/.ssh/authorized_keys"))
  end

  test "blocks Write to .ssh/config" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Write", "/home/user/.ssh/config"))
  end

  # ── other write tools ───────────────────────────────────────────────────────

  test "blocks Edit to .pem file" do
    assert BlockSecretsWrite.matches?(policy(), ctx("Edit", "/certs/server.pem"))
  end

  test "blocks MultiEdit to .key file" do
    assert BlockSecretsWrite.matches?(policy(), ctx("MultiEdit", "/certs/server.key"))
  end

  # ── no-match cases ──────────────────────────────────────────────────────────

  test "does not block Read of .pem file" do
    refute BlockSecretsWrite.matches?(policy(), ctx("Read", "/certs/server.pem"))
  end

  test "does not block Write to non-secret file" do
    refute BlockSecretsWrite.matches?(policy(), ctx("Write", "/project/lib/foo.ex"))
  end

  test "does not block Write to file with key in name but not extension" do
    refute BlockSecretsWrite.matches?(policy(), ctx("Write", "/project/lib/api_key_helper.ex"))
  end

  test "does not block Bash tool" do
    refute BlockSecretsWrite.matches?(policy(), %Context{
             tool: "Bash",
             resource_path: "/certs/server.pem"
           })
  end

  # ── allowPaths condition ────────────────────────────────────────────────────

  test "allowPaths escapes the deny for listed path" do
    p = policy(%{"allowPaths" => ["/test/fixtures/test.pem"]})
    refute BlockSecretsWrite.matches?(p, ctx("Write", "/test/fixtures/test.pem"))
    assert BlockSecretsWrite.matches?(p, ctx("Write", "/certs/server.pem"))
  end
end
