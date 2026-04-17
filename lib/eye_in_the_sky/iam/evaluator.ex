defmodule EyeInTheSky.IAM.Evaluator do
  @moduledoc """
  Evaluates an `EyeInTheSky.IAM.Context` against the enabled policies and
  returns an `EyeInTheSky.IAM.Decision`.

  ## Algorithm

  1. Fetch candidate policies from the cache.
  2. Coarse-filter: `agent_type` and `action` must match (or be `"*"`).
  3. For each survivor, check project, resource glob, and condition.
  4. Partition full matches into `denies`, `allows`, `instructs`.
  5. Resolve permission:
     * Any `deny`   → winner = lowest rank `{-priority, id}`; `default?: false`.
     * Else any `allow` → winner = lowest rank; `default?: false`.
     * Else → fallback permission; `winner = nil`; `default?: true`.
  6. Instructions are always attached (sorted by rank), regardless of the
     permission or whether fallback fired.
  """

  alias EyeInTheSky.IAM.ConditionEval
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Decision
  alias EyeInTheSky.IAM.Matcher
  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSky.IAM.PolicyCache

  @telemetry_decide [:eye_in_the_sky, :iam, :decide]

  @type opts :: [fallback_permission: :allow | :deny, policies: [Policy.t()]]

  @doc """
  Evaluate a normalized context and return a `Decision`.

  Options:

    * `:fallback_permission` — `:allow` (default) or `:deny` when no
      deny/allow policy matches.
    * `:policies` — explicit policy list, bypassing the cache. Intended for
      tests and the simulator.
  """
  @spec decide(Context.t(), opts()) :: Decision.t()
  def decide(%Context{} = ctx, opts \\ []) do
    start = System.monotonic_time()
    fallback = Keyword.get(opts, :fallback_permission, :allow)

    {policies, cache_result} =
      case Keyword.fetch(opts, :policies) do
        {:ok, list} -> {list, :bypass}
        :error -> PolicyCache.all_enabled()
      end

    matches = Enum.filter(policies, &matches?(&1, ctx))

    {denies, allows, instructs} = partition_by_effect(matches)

    {permission, winner, default?} = resolve_permission(denies, allows, fallback)

    instructions =
      instructs
      |> Enum.sort_by(&rank/1)
      |> Enum.map(fn p -> %{policy: p, message: message_for(p)} end)

    decision = %Decision{
      permission: permission,
      winning_policy: winner,
      reason: winner && message_for(winner),
      instructions: instructions,
      default?: default?,
      evaluated_count: length(policies)
    }

    emit_telemetry(start, decision, cache_result)
    decision
  end

  # ── matching ────────────────────────────────────────────────────────────────

  defp matches?(%Policy{} = p, %Context{} = ctx) do
    agent_matches?(p, ctx) and
      action_matches?(p, ctx) and
      project_matches?(p, ctx) and
      specialized_matches?(p, ctx)
  end

  # System policies with `builtin_matcher` bypass declarative resource_glob
  # and ConditionEval — they own their match logic in an Elixir module.
  defp specialized_matches?(%Policy{builtin_matcher: key} = p, %Context{} = ctx)
       when is_binary(key) do
    case EyeInTheSky.IAM.BuiltinMatcher.Registry.fetch(key) do
      {:ok, module} ->
        safe_builtin_match(module, p, ctx)

      :error ->
        :telemetry.execute(
          [:eye_in_the_sky, :iam, :builtin_matcher, :unknown_key],
          %{count: 1},
          %{policy_id: p.id, key: key}
        )

        false
    end
  end

  defp specialized_matches?(%Policy{} = p, %Context{} = ctx) do
    resource_matches?(p, ctx) and ConditionEval.matches?(p.condition, ctx, p.id)
  end

  defp safe_builtin_match(module, %Policy{} = p, %Context{} = ctx) do
    module.matches?(p, ctx)
  rescue
    e ->
      :telemetry.execute(
        [:eye_in_the_sky, :iam, :builtin_matcher, :error],
        %{count: 1},
        %{policy_id: p.id, module: module, kind: :error, reason: Exception.message(e)}
      )

      false
  catch
    kind, reason ->
      :telemetry.execute(
        [:eye_in_the_sky, :iam, :builtin_matcher, :error],
        %{count: 1},
        %{policy_id: p.id, module: module, kind: kind, reason: inspect(reason)}
      )

      false
  end

  defp agent_matches?(%Policy{agent_type: "*"}, _ctx), do: true
  defp agent_matches?(%Policy{agent_type: at}, %Context{agent_type: at}), do: true
  defp agent_matches?(_, _), do: false

  defp action_matches?(%Policy{action: "*"}, _ctx), do: true
  defp action_matches?(%Policy{action: a}, %Context{tool: a}), do: true
  defp action_matches?(_, _), do: false

  # project_id is canonical. If set, path is ignored for matching.
  defp project_matches?(%Policy{project_id: pid}, %Context{project_id: pid})
       when not is_nil(pid),
       do: true

  defp project_matches?(%Policy{project_id: pid}, _) when not is_nil(pid), do: false

  defp project_matches?(%Policy{project_id: nil, project_path: pattern}, %Context{
         project_path: value
       }) do
    Matcher.match_glob?(value, pattern)
  end

  defp resource_matches?(%Policy{resource_glob: nil}, _ctx), do: true

  defp resource_matches?(%Policy{resource_glob: pattern}, %Context{resource_path: value}) do
    Matcher.match_glob?(value, pattern)
  end

  # ── partition + resolution ──────────────────────────────────────────────────

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

  # Rank tuple: lower is better. `-priority` sorts high priority first; `id`
  # sorts lower id first as the tie-break.
  defp rank(%Policy{priority: priority, id: id}), do: {-priority, id || 0}

  defp message_for(%Policy{message: nil, name: name, effect: effect}),
    do: "#{effect}: #{name}"

  defp message_for(%Policy{message: msg}), do: msg

  # ── telemetry ───────────────────────────────────────────────────────────────

  defp emit_telemetry(start, %Decision{} = d, cache_result) do
    duration = System.monotonic_time() - start

    :telemetry.execute(
      @telemetry_decide,
      %{duration: duration, evaluated_count: d.evaluated_count},
      %{
        permission: d.permission,
        default?: d.default?,
        cache: cache_result,
        instruction_count: length(d.instructions)
      }
    )
  end
end
