defmodule EyeInTheSky.IAM.Decision do
  @moduledoc """
  Output of `EyeInTheSky.IAM.Evaluator.decide/2`.

  Fields:

    * `:permission` — the authorization outcome: `:allow` or `:deny`.
    * `:winning_policy` — the policy that produced the permission, or `nil`
      when the permission came from the fallback.
    * `:winning_source` — the evaluation source (`:global` or a document
      tuple) that contributed the winning policy, or `nil` on fallback.
    * `:reason` — human-readable string attached to the winning policy (or
      the fallback).
    * `:instructions` — accumulated advisory output from every matching
      `instruct` policy, always attached regardless of the permission.
      Each entry is `%{policy: Policy.t(), message: String.t(), source: EvaluationSource.t()}`.
    * `:default?` — `true` iff the permission came from the fallback.
      **Note:** this does NOT imply `instructions == []`; advisory matches
      can fire even when permission falls through.
    * `:evaluated_count` — total number of evaluation candidates checked
      (the same policy appearing globally and via a document is counted
      twice — reflects actual evaluation work).
  """

  alias EyeInTheSky.IAM.EvaluationSource
  alias EyeInTheSky.IAM.Policy

  @type instruction :: %{
          policy: Policy.t(),
          message: String.t(),
          source: EvaluationSource.t()
        }

  @type t :: %__MODULE__{
          permission: :allow | :deny,
          winning_policy: Policy.t() | nil,
          winning_source: EvaluationSource.t() | nil,
          reason: String.t() | nil,
          instructions: [instruction()],
          default?: boolean(),
          evaluated_count: non_neg_integer()
        }

  defstruct permission: :allow,
            winning_policy: nil,
            winning_source: nil,
            reason: nil,
            instructions: [],
            default?: false,
            evaluated_count: 0
end
