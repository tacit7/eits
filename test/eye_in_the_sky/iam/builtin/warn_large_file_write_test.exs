defmodule EyeInTheSky.IAM.Builtin.WarnLargeFileWriteTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.WarnLargeFileWrite
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @default_max 100_000

  defp ctx(tool, content), do: %Context{tool: tool, resource_content: content}
  defp policy(cond \\ nil), do: %Policy{condition: cond}

  defp content_of(bytes), do: String.duplicate("x", bytes)

  test "does not match content under default threshold" do
    refute WarnLargeFileWrite.matches?(policy(), ctx("Write", content_of(@default_max - 1)))
  end

  test "does not match content at exactly default threshold" do
    refute WarnLargeFileWrite.matches?(policy(), ctx("Write", content_of(@default_max)))
  end

  test "matches content over default threshold" do
    assert WarnLargeFileWrite.matches?(policy(), ctx("Write", content_of(@default_max + 1)))
  end

  test "matches on Edit tool" do
    assert WarnLargeFileWrite.matches?(policy(), ctx("Edit", content_of(@default_max + 1)))
  end

  test "matches on MultiEdit tool" do
    assert WarnLargeFileWrite.matches?(policy(), ctx("MultiEdit", content_of(@default_max + 1)))
  end

  test "does not match on Bash tool" do
    refute WarnLargeFileWrite.matches?(policy(), ctx("Bash", content_of(@default_max + 1)))
  end

  test "does not match on Read tool" do
    refute WarnLargeFileWrite.matches?(policy(), ctx("Read", content_of(@default_max + 1)))
  end

  test "respects custom maxBytes condition" do
    p = policy(%{"maxBytes" => 500})
    refute WarnLargeFileWrite.matches?(p, ctx("Write", content_of(500)))
    assert WarnLargeFileWrite.matches?(p, ctx("Write", content_of(501)))
  end

  test "ignores invalid maxBytes and falls back to default" do
    p = policy(%{"maxBytes" => -1})
    refute WarnLargeFileWrite.matches?(p, ctx("Write", content_of(@default_max)))
    assert WarnLargeFileWrite.matches?(p, ctx("Write", content_of(@default_max + 1)))
  end

  test "does not match nil content" do
    refute WarnLargeFileWrite.matches?(policy(), %Context{tool: "Write", resource_content: nil})
  end
end
