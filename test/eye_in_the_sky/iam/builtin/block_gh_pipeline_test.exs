defmodule EyeInTheSky.IAM.Builtin.BlockGhPipelineTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockGhPipeline
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp policy(cond \\ nil), do: %Policy{condition: cond}
  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  # ── positive matches ────────────────────────────────────────────────────────

  test "blocks gh run rerun" do
    assert BlockGhPipeline.matches?(policy(), ctx("gh run rerun 12345"))
  end

  test "blocks gh run cancel" do
    assert BlockGhPipeline.matches?(policy(), ctx("gh run cancel 12345"))
  end

  test "blocks gh workflow run" do
    assert BlockGhPipeline.matches?(policy(), ctx("gh workflow run deploy.yml"))
  end

  test "blocks gh workflow enable" do
    assert BlockGhPipeline.matches?(policy(), ctx("gh workflow enable nightly.yml"))
  end

  test "blocks gh workflow disable" do
    assert BlockGhPipeline.matches?(policy(), ctx("gh workflow disable staging.yml"))
  end

  test "blocks gh workflow run with --ref flag" do
    assert BlockGhPipeline.matches?(policy(), ctx("gh workflow run ci.yml --ref main"))
  end

  # ── negative — safe gh commands ─────────────────────────────────────────────

  test "does not block gh pr create" do
    refute BlockGhPipeline.matches?(policy(), ctx("gh pr create --title 'fix'"))
  end

  test "does not block gh repo clone" do
    refute BlockGhPipeline.matches?(policy(), ctx("gh repo clone owner/repo"))
  end

  test "does not block gh workflow list" do
    refute BlockGhPipeline.matches?(policy(), ctx("gh workflow list"))
  end

  test "does not block gh run list" do
    refute BlockGhPipeline.matches?(policy(), ctx("gh run list"))
  end

  test "does not block gh run view" do
    refute BlockGhPipeline.matches?(policy(), ctx("gh run view 12345"))
  end

  test "does not block non-Bash tool" do
    refute BlockGhPipeline.matches?(policy(), %Context{tool: "Read", resource_path: "/gh/run"})
  end

  # ── allowWorkflows condition ────────────────────────────────────────────────

  test "allowWorkflows escapes deny for listed workflow" do
    p = policy(%{"allowWorkflows" => ["deploy.yml"]})
    refute BlockGhPipeline.matches?(p, ctx("gh workflow run deploy.yml"))
    assert BlockGhPipeline.matches?(p, ctx("gh workflow run dangerous.yml"))
  end

  test "allowWorkflows with multiple entries" do
    p = policy(%{"allowWorkflows" => ["deploy.yml", "release.yml"]})
    refute BlockGhPipeline.matches?(p, ctx("gh workflow run release.yml"))
    assert BlockGhPipeline.matches?(p, ctx("gh workflow run staging.yml"))
  end
end
