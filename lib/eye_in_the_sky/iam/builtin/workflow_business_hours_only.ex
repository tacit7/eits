defmodule EyeInTheSky.IAM.Builtin.WorkflowBusinessHoursOnly do
  @moduledoc """
  Enforces that certain tool actions only run within a time window (default: 09:00–17:00 UTC).

  The actual time check is delegated to the `time_between` condition predicate.
  This matcher is just a label — the condition does the work.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @impl true
  def matches?(%Policy{}, %Context{}), do: true

  @impl true
  def instruction_message(%Policy{message: msg}, _ctx) when is_binary(msg), do: msg
  def instruction_message(_policy, _ctx), do: nil
end
