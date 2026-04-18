defmodule EyeInTheSky.IAM.BuiltinMatcher do
  @moduledoc """
  Behaviour for built-in policy matchers.

  System policies may set `builtin_matcher` to a stable registry key
  (see `EyeInTheSky.IAM.BuiltinMatcher.Registry`). When present, the
  evaluator delegates the `matches?` check to the registered module
  instead of evaluating `resource_glob` and `condition` declaratively.

  This lets built-ins implement shell-aware parsing, filesystem
  resolution, and repo-state inspection without polluting
  `ConditionEval` with impure predicates or exposing those powers to
  user-authored policies.

  Contract:

    * `matches?/2` receives the policy struct (for params stored in
      `condition`, `message`, etc.) and the normalized IAM context.
    * Must return a boolean. Any failure inside the matcher should be
      caught and reported via telemetry; the matcher itself should
      return `false` on error (fail closed — the decision is "does not
      match", not "cannot decide").
    * Must be pure with respect to the DB. Matchers may shell out
      (e.g. `git rev-parse`), read the filesystem, or inspect
      environment variables, but must not touch Repo.
  """

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @callback matches?(Policy.t(), Context.t()) :: boolean()

  @doc """
  Optional callback for matchers that produce a dynamic instruction message
  based on context (e.g., including redacted content). Returns `nil` to fall
  back to the policy's static `message` field.
  """
  @callback instruction_message(Policy.t(), Context.t()) :: String.t() | nil
  @optional_callbacks [instruction_message: 2]
end
