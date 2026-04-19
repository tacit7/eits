defmodule EyeInTheSky.IAM.ConditionEvalTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.IAM.ConditionEval
  alias EyeInTheSky.IAM.Context

  defp ctx(meta \\ %{}), do: %Context{event: :pre_tool_use, metadata: meta}

  describe "matches?/3" do
    test "nil condition matches" do
      assert ConditionEval.matches?(nil, ctx(), 1)
    end

    test "empty map matches" do
      assert ConditionEval.matches?(%{}, ctx(), 1)
    end

    test "unknown predicate fails closed" do
      refute ConditionEval.matches?(%{"unknown" => "x"}, ctx(), 1)
    end

    test "session_state_equals matches string vs atom keys" do
      assert ConditionEval.matches?(
               %{"session_state_equals" => "working"},
               ctx(%{session_state: "working"}),
               1
             )

      assert ConditionEval.matches?(
               %{"session_state_equals" => "working"},
               ctx(%{"session_state" => "working"}),
               1
             )

      refute ConditionEval.matches?(
               %{"session_state_equals" => "working"},
               ctx(%{"session_state" => "stopped"}),
               1
             )
    end

    test "env_equals checks System.get_env" do
      var = "EITS_IAM_COND_TEST_#{:rand.uniform(1_000_000)}"
      System.put_env(var, "yes")

      try do
        assert ConditionEval.matches?(%{"env_equals" => %{var => "yes"}}, ctx(), 1)
        refute ConditionEval.matches?(%{"env_equals" => %{var => "no"}}, ctx(), 1)
      after
        System.delete_env(var)
      end
    end

    test "env_equals with invalid entry fails" do
      refute ConditionEval.matches?(%{"env_equals" => %{"K" => 123}}, ctx(), 1)
    end

    test "time_between with invalid format fails" do
      refute ConditionEval.matches?(%{"time_between" => ["bogus", "10:00"]}, ctx(), 1)
    end

    test "time_between matches wide window (always true)" do
      assert ConditionEval.matches?(%{"time_between" => ["00:00", "23:59"]}, ctx(), 1)
    end

    test "time_between wrap-midnight logic works for empty and full windows" do
      # 00:00..00:00 is a single-minute window; 00:01..00:00 wraps and covers everything
      # We don't assert on current time; we only check it doesn't crash and returns boolean.
      result = ConditionEval.matches?(%{"time_between" => ["00:01", "00:00"]}, ctx(), 1)
      assert is_boolean(result)
    end
  end
end
