defmodule EyeInTheSky.IAM.Simulator do
  @moduledoc """
  Dry-run simulator for the IAM policy engine.

  Given a hypothetical `EyeInTheSky.IAM.Context`, this module evaluates every
  enabled policy (from the cache, or an explicit list) using the same matching
  pipeline as `EyeInTheSky.IAM.Evaluator`, and returns a structured trace:

    * the final `Decision`,
    * a per-policy trace entry with match/miss-reason,
    * the winning policy id (if any),
    * whether the decision fell back to the default permission.

  The simulator shares matching code with the evaluator via
  `EyeInTheSky.IAM.Evaluator.trace_policy/3` — no logic is duplicated.

  ## Built-in matchers

  By default, built-in matchers run normally. Some (e.g. `block_work_on_main`,
  `block_push_master`) shell out to `git` to inspect the current branch. This
  is fine for simulations run inside a known working directory, but can be
  surprising in the LiveView page where the process cwd is the release root.

  Pass `skip_builtins: true` to bypass dispatch; built-in policies will then
  match on the coarse axes (agent_type, action, project) only. The LiveView
  UI exposes this as a checkbox.

  ## Telemetry

  Emits `[:eye_in_the_sky, :iam, :simulate]` with the trace count. The real
  `[:eye_in_the_sky, :iam, :decide]` event is **not** emitted — simulated runs
  must not pollute production telemetry.

  ## Persistence

  The simulator never writes to the database and never mutates policy state.
  """

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Decision
  alias EyeInTheSky.IAM.Evaluator
  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSky.IAM.PolicyCache

  @telemetry_simulate [:eye_in_the_sky, :iam, :simulate]

  @type miss_reason ::
          :agent_type
          | :action
          | :project
          | :resource
          | :condition
          | :builtin_matcher
          | :builtin_error
          | :disabled

  @type trace_entry :: %{
          policy: Policy.t(),
          matched?: boolean(),
          reason: :ok | {:miss, miss_reason()}
        }

  @type result :: %{
          decision: Decision.t(),
          traces: [trace_entry()],
          winner_id: integer() | nil,
          fallback?: boolean()
        }

  @type opts :: [
          fallback_permission: :allow | :deny,
          policies: [Policy.t()],
          include_disabled: boolean(),
          skip_builtins: boolean()
        ]

  @doc """
  Run a simulation. Returns a full trace — see module doc.

  Options:

    * `:fallback_permission` — `:allow` (default) or `:deny`.
    * `:policies` — explicit policy list. If omitted, uses the cache via
      `PolicyCache.all_enabled/0`.
    * `:include_disabled` — include disabled policies in the trace, marked
      with `{:miss, :disabled}`. Has no effect when `:policies` is passed.
      Default `false`.
    * `:skip_builtins` — bypass built-in matcher dispatch. Default `false`.
  """
  @spec simulate(Context.t(), opts()) :: result()
  def simulate(%Context{} = ctx, opts \\ []) do
    fallback = Keyword.get(opts, :fallback_permission, :allow)
    skip_builtins = Keyword.get(opts, :skip_builtins, false)

    policies = load_policies(opts)

    traces =
      Enum.map(policies, fn p ->
        cond do
          not p.enabled ->
            %{policy: p, matched?: false, reason: {:miss, :disabled}}

          true ->
            reason = Evaluator.trace_policy(p, ctx, skip_builtins: skip_builtins)
            %{policy: p, matched?: reason == :ok, reason: reason}
        end
      end)

    matches = for t <- traces, t.matched?, do: t.policy

    {denies, allows, instructs} = partition_by_effect(matches)

    {permission, winner, fallback?} = resolve_permission(denies, allows, fallback)

    instructions =
      instructs
      |> Enum.sort_by(&rank/1)
      |> Enum.map(fn p -> %{policy: p, message: message_for(p)} end)

    decision = %Decision{
      permission: permission,
      winning_policy: winner,
      reason: winner && message_for(winner),
      instructions: instructions,
      default?: fallback?,
      evaluated_count: length(policies)
    }

    :telemetry.execute(
      @telemetry_simulate,
      %{traces: length(traces), matches: length(matches)},
      %{permission: permission, fallback?: fallback?, skip_builtins: skip_builtins}
    )

    %{
      decision: decision,
      traces: traces,
      winner_id: winner && winner.id,
      fallback?: fallback?
    }
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp load_policies(opts) do
    case Keyword.fetch(opts, :policies) do
      {:ok, list} ->
        list

      :error ->
        {enabled, _cache_result} = PolicyCache.all_enabled()

        if Keyword.get(opts, :include_disabled, false) do
          enabled_ids = MapSet.new(enabled, & &1.id)

          disabled =
            IAM.list_policies()
            |> Enum.reject(&MapSet.member?(enabled_ids, &1.id))

          enabled ++ disabled
        else
          enabled
        end
    end
  end

  defp partition_by_effect(policies) do
    Enum.reduce(policies, {[], [], []}, fn p, {d, a, i} ->
      case p.effect do
        "deny" -> {[p | d], a, i}
        "allow" -> {d, [p | a], i}
        "instruct" -> {d, a, [p | i]}
        _ -> {d, a, i}
      end
    end)
  end

  defp resolve_permission([_ | _] = denies, _allows, _fallback) do
    {:deny, Enum.min_by(denies, &rank/1), false}
  end

  defp resolve_permission([], [_ | _] = allows, _fallback) do
    {:allow, Enum.min_by(allows, &rank/1), false}
  end

  defp resolve_permission([], [], fallback) do
    {fallback, nil, true}
  end

  defp rank(%Policy{priority: priority, id: id}), do: {-priority, id || 0}

  defp message_for(%Policy{message: nil, name: name, effect: effect}),
    do: "#{effect}: #{name}"

  defp message_for(%Policy{message: msg}), do: msg
end
