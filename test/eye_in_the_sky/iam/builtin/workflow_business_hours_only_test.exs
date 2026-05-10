defmodule EyeInTheSky.IAM.Builtin.WorkflowBusinessHoursOnlyTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.WorkflowBusinessHoursOnly
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx, do: %Context{tool: "Bash", agent_type: "root"}

  describe "matches?/2" do
    test "matches when condition is nil (no time gating)" do
      policy = %Policy{id: 1, condition: nil}
      assert WorkflowBusinessHoursOnly.matches?(policy, ctx())
    end

    test "matches when condition is empty map" do
      policy = %Policy{id: 1, condition: %{}}
      assert WorkflowBusinessHoursOnly.matches?(policy, ctx())
    end

    test "matches when current UTC time is inside a wide window covering all 24h" do
      policy = %Policy{id: 1, condition: %{"time_between" => ["00:00", "23:59"]}}
      assert WorkflowBusinessHoursOnly.matches?(policy, ctx())
    end

    test "does not match when current UTC time is outside a degenerate single-minute window" do
      # Pick a minute that cannot equal `now` — anchor on current minute and shift by 30.
      %DateTime{hour: h, minute: m} = DateTime.utc_now()
      far = rem(m + 30, 60)
      far_str = String.pad_leading(Integer.to_string(far), 2, "0")
      hh = String.pad_leading(Integer.to_string(h), 2, "0")

      cond = %{"time_between" => ["#{hh}:#{far_str}", "#{hh}:#{far_str}"]}
      policy = %Policy{id: 42, condition: cond}
      refute WorkflowBusinessHoursOnly.matches?(policy, ctx())
    end

    test "does not match when condition is malformed" do
      policy = %Policy{id: 99, condition: %{"time_between" => ["bogus", "also-bogus"]}}
      refute WorkflowBusinessHoursOnly.matches?(policy, ctx())
    end

    test "matches a wrap-around window that includes every minute" do
      # from > to means wrap. 00:01 -> 00:00 spans the entire day.
      policy = %Policy{id: 7, condition: %{"time_between" => ["00:01", "00:00"]}}
      assert WorkflowBusinessHoursOnly.matches?(policy, ctx())
    end

    test "unknown predicate keys cause non-match" do
      policy = %Policy{id: 5, condition: %{"some_unknown_predicate" => "x"}}
      refute WorkflowBusinessHoursOnly.matches?(policy, ctx())
    end

    test "evaluates against a Context struct without raising" do
      policy = %Policy{id: 1, condition: %{}}

      context = %Context{
        event: :pre_tool_use,
        agent_type: "root",
        tool: "Bash",
        resource_type: :command,
        resource_content: "echo hi"
      }

      assert WorkflowBusinessHoursOnly.matches?(policy, context)
    end
  end

  describe "instruction_message/2" do
    test "returns the policy's message when set" do
      policy = %Policy{message: "Outside business hours."}
      assert WorkflowBusinessHoursOnly.instruction_message(policy, ctx()) ==
               "Outside business hours."
    end

    test "returns nil when message is nil" do
      policy = %Policy{message: nil}
      assert WorkflowBusinessHoursOnly.instruction_message(policy, ctx()) == nil
    end

    test "returns nil for non-binary message values" do
      policy = %Policy{message: 123}
      assert WorkflowBusinessHoursOnly.instruction_message(policy, ctx()) == nil
    end
  end
end
