defmodule EyeInTheSky.IAM.Decision do
  @moduledoc """
  Output of `EyeInTheSky.IAM.Evaluator.decide/2`.

  Fields:

    * `:permission` — the authorization outcome: `:allow` or `:deny`.
    * `:winning_policy` — the policy that produced the permission, or `nil`
      when the permission came from the fallback.
    * `:reason` — human-readable string attached to the winning policy (or
      the fallback).
    * `:instructions` — accumulated advisory output from every matching
      `instruct` policy, always attached regardless of the permission.
      Each entry is `%{policy: Policy.t(), message: String.t()}`.
    * `:default?` — `true` iff the permission came from the fallback.
      **Note:** this does NOT imply `instructions == []`; advisory matches
      can fire even when permission falls through.
    * `:evaluated_count` — total number of candidate policies evaluated (for
      telemetry/debug).
  """

  alias EyeInTheSky.IAM.Policy

  @type instruction :: %{policy: Policy.t(), message: String.t()}

  @type t :: %__MODULE__{
          permission: :allow | :deny,
          winning_policy: Policy.t() | nil,
          reason: String.t() | nil,
          instructions: [instruction()],
          default?: boolean(),
          evaluated_count: non_neg_integer()
        }

  defstruct permission: :allow,
            winning_policy: nil,
            reason: nil,
            instructions: [],
            default?: false,
            evaluated_count: 0
end
