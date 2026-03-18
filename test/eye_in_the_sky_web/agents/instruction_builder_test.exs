defmodule EyeInTheSkyWeb.Agents.InstructionBuilderTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Agents.InstructionBuilder

  describe "build/1" do
    test "returns explicit instructions when no worktree" do
      assert InstructionBuilder.build(instructions: "Do the thing") == "Do the thing"
    end

    test "falls back to description when no instructions and no worktree" do
      assert InstructionBuilder.build(description: "Fix bug") == "Fix bug"
    end

    test "falls back to default description when neither instructions nor description given" do
      assert InstructionBuilder.build([]) == "Agent session"
    end

    test "appends git/PR workflow suffix when worktree is set" do
      result = InstructionBuilder.build(instructions: "Do the thing", worktree: "my-feature")

      assert String.starts_with?(result, "Do the thing")
      assert result =~ "git push gitea worktree-my-feature"
      assert result =~ "tea pr create"
      assert result =~ "--head worktree-my-feature"
      assert result =~ "i-end-session"
    end

    test "uses description as base when worktree is set but no explicit instructions" do
      result = InstructionBuilder.build(description: "Build X", worktree: "build-x")

      assert String.starts_with?(result, "Build X")
      assert result =~ "git push gitea worktree-build-x"
    end

    test "uses default description as base when worktree set but no instructions or description" do
      result = InstructionBuilder.build(worktree: "my-worktree")

      assert String.starts_with?(result, "Agent session")
      assert result =~ "git push gitea worktree-my-worktree"
    end
  end
end
