defmodule EyeInTheSky.Tasks.WorkflowStateTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Tasks.WorkflowState

  describe "resolve_alias/1" do
    test "done -> Done" do
      assert WorkflowState.resolve_alias("done") == {:ok, "Done"}
    end

    test "start -> In Progress" do
      assert WorkflowState.resolve_alias("start") == {:ok, "In Progress"}
    end

    test "in-review -> In Review" do
      assert WorkflowState.resolve_alias("in-review") == {:ok, "In Review"}
    end

    test "review -> In Review" do
      assert WorkflowState.resolve_alias("review") == {:ok, "In Review"}
    end

    test "todo -> To Do" do
      assert WorkflowState.resolve_alias("todo") == {:ok, "To Do"}
    end

    test "alias matching is case-insensitive" do
      assert WorkflowState.resolve_alias("DONE") == {:ok, "Done"}
      assert WorkflowState.resolve_alias("In-Review") == {:ok, "In Review"}
    end

    test "nil returns :no_alias" do
      assert WorkflowState.resolve_alias(nil) == {:error, :no_alias}
    end

    test "numeric string returns :no_alias (treat as state_id, not alias)" do
      assert WorkflowState.resolve_alias("3") == {:error, :no_alias}
      assert WorkflowState.resolve_alias("4") == {:error, :no_alias}
    end

    test "unknown string returns :invalid_alias" do
      assert WorkflowState.resolve_alias("purple") == {:error, :invalid_alias}
      assert WorkflowState.resolve_alias("finished") == {:error, :invalid_alias}
    end
  end
end
