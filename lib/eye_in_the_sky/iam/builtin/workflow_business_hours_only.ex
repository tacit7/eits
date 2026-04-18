defmodule EyeInTheSky.IAM.Builtin.WorkflowBusinessHoursOnly do
  @moduledoc """
  Enforces that certain tool actions only run within a configured time window.

  Default: 09:00–17:00 UTC (operator-editable via the `condition` field).

  Builtin matchers bypass the declarative ConditionEval dispatch, so this module
  evaluates the `time_between` predicate directly from the policy's condition map.
  A policy with no condition (or an empty condition) matches at all times.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.ConditionEval
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @impl true
  def matches?(%Policy{condition: condition, id: id} = _p, %Context{} = ctx) do
    ConditionEval.matches?(condition, ctx, id)
  end

  @impl true
  def instruction_message(%Policy{message: msg}, _ctx) when is_binary(msg), do: msg
  def instruction_message(_policy, _ctx), do: nil
end
