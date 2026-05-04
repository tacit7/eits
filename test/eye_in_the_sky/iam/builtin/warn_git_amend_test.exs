defmodule EyeInTheSky.IAM.Builtin.WarnGitAmendTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.WarnGitAmend
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  # ── git commit --amend ──────────────────────────────────────────────────────

  test "matches git commit --amend" do
    assert WarnGitAmend.matches?(%Policy{}, ctx("git commit --amend"))
  end

  test "matches git commit --amend --no-edit" do
    assert WarnGitAmend.matches?(%Policy{}, ctx("git commit --amend --no-edit"))
  end

  test "matches git commit -m 'fix' --amend" do
    assert WarnGitAmend.matches?(%Policy{}, ctx(~s|git commit -m "fix" --amend|))
  end

  # ── git rebase -i / --interactive ──────────────────────────────────────────

  test "matches git rebase -i HEAD~3" do
    assert WarnGitAmend.matches?(%Policy{}, ctx("git rebase -i HEAD~3"))
  end

  test "matches git rebase --interactive main" do
    assert WarnGitAmend.matches?(%Policy{}, ctx("git rebase --interactive main"))
  end

  # ── no-match cases ──────────────────────────────────────────────────────────

  test "does not match plain git commit" do
    refute WarnGitAmend.matches?(%Policy{}, ctx(~s|git commit -m "add feature"|))
  end

  test "does not match git rebase without -i flag" do
    refute WarnGitAmend.matches?(%Policy{}, ctx("git rebase main"))
  end

  test "does not match non-Bash tool" do
    ctx = %Context{tool: "Write", resource_content: "git commit --amend"}
    refute WarnGitAmend.matches?(%Policy{}, ctx)
  end

  test "does not match nil content" do
    refute WarnGitAmend.matches?(%Policy{}, %Context{tool: "Bash", resource_content: nil})
  end

  test "does not match unrelated Bash command" do
    refute WarnGitAmend.matches?(%Policy{}, ctx("mix compile"))
  end
end
