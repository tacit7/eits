defmodule EyeInTheSky.IAM.Evaluator do
  @moduledoc """
  Evaluates an `EyeInTheSky.IAM.Context` against the enabled policies and
  returns an `EyeInTheSky.IAM.Decision`.

  ## Algorithm

  1. Build evaluation candidates: global policies from `PolicyCache.all_enabled/0`
     plus document-contributed policies from `PolicyCache.for_agent_type/1`.
     Each candidate is `%{policy: Policy.t(), source: EvaluationSource.t()}`.
  2. Filter candidates: `candidate_matches?/2` runs the full matching pipeline
     for each, passing the source so `agent_matches?/3` can bypass policy-level
     `agent_type` for document-sourced candidates (the document attachment IS
     the scope).
  3. Partition full matches into `denies`, `allows`, `instructs`.
  4. Resolve permission:
     * Any `deny`   → winner = lowest rank `{-priority, id, source_rank}`; `default?: false`.
     * Else any `allow` → winner = lowest rank; `default?: false`.
     * Else → fallback permission; `winner = nil`; `default?: true`.
  5. Instructions are always attached (sorted by rank), regardless of the
     permission or whether fallback fired.

  ## Source metadata

  Winning source and instruction sources are preserved in the `Decision` struct
  via `EyeInTheSky.IAM.EvaluationSource`. All display paths should call
  `EvaluationSource.label/1` — never pattern-match on the raw tuple in UI code.
  """

  alias EyeInTheSky.IAM.ConditionEval
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Decision
  alias EyeInTheSky.IAM.EvaluationSource
  alias EyeInTheSky.IAM.Matcher
  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSky.IAM.PolicyCache

  @telemetry_decide [:eye_in_the_sky, :iam, :decide]

  @type evaluation_candidate :: %{policy: Policy.t(), source: EvaluationSource.t()}

  @type opts :: [
          fallback_permission: :allow | :deny,
          policies: [Policy.t()],
          document_candidates: [map()]
        ]

  @doc """
  Evaluate a normalized context and return a `Decision`.

  Options:

    * `:fallback_permission` — `:allow` (default) or `:deny` when no
      deny/allow policy matches.
    * `:policies` — explicit global policy list, bypassing the cache. Intended
      for tests and the simulator.
    * `:document_candidates` — explicit document candidate list (maps with
      `:policy`, `:document`, `:attached_agent_type`), bypassing
      `PolicyCache.for_agent_type/1`. Lets tests inject either pool
      independently.
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

    doc_candidates_raw =
      case Keyword.fetch(opts, :document_candidates) do
        {:ok, list} ->
          list

        :error ->
          # When opts[:policies] is provided (test injection / explicit bypass),
          # skip the document cache lookup too — callers in that mode don't own
          # a DB connection and don't expect side effects.
          # opts[:document_candidates] can still be provided independently.
          if Keyword.has_key?(opts, :policies) do
            []
          else
            if is_binary(ctx.agent_type) and ctx.agent_type not in ["", "*"] do
              PolicyCache.for_agent_type(ctx.agent_type)
            else
              []
            end
          end
      end

    global_candidates = Enum.map(policies, &%{policy: &1, source: :global})

    document_candidates =
      Enum.map(doc_candidates_raw, fn %{policy: p, document: doc, attached_agent_type: at} ->
        %{policy: p, source: {:document, doc.id, doc.name, at}}
      end)

    # No dedup — same policy from two sources = two trace entries (intentional)
    all_candidates = global_candidates ++ document_candidates

    matches = Enum.filter(all_candidates, &candidate_matches?(&1, ctx))

    {denies, allows, instructs} = partition_by_effect(matches)

    {permission, winner, winner_source, default?} = resolve_permission(denies, allows, fallback)

    instructions =
      instructs
      |> Enum.sort_by(&rank/1)
      |> Enum.map(fn %{policy: p, source: src} ->
        %{policy: p, message: instruct_message(p, ctx), source: src}
      end)

    decision = %Decision{
      permission: permission,
      winning_policy: winner,
      winning_source: winner_source,
      reason: winner && message_for(winner),
      instructions: instructions,
      default?: default?,
      evaluated_count: length(all_candidates)
    }

    emit_telemetry(start, decision, cache_result)
    decision
  end

  # ── matching ────────────────────────────────────────────────────────────────

  @doc """
  Trace why a policy matched or missed against a context. Returns `:ok` on a
  full match, or `{:miss, axis}` where axis is one of
  `:agent_type | :action | :project | :resource | :condition | :builtin_matcher | :builtin_error`.

  Used by the evaluator for matching and by `EyeInTheSky.IAM.Simulator` for
  per-policy dry-run traces. Callers that only need a boolean can compare the
  result to `:ok`.

  Options:

    * `:source` — `EvaluationSource.t()` for this candidate. Defaults to
      `:global`. Document-sourced candidates bypass `agent_type` matching.
    * `:skip_builtins` — bypass built-in matcher dispatch (useful for
      simulation to avoid shelling out). When skipped, a built-in policy passes
      as long as the coarse axes match.
  """
  @spec trace_policy(Policy.t(), Context.t(), keyword()) ::
          :ok | {:miss, atom()}
  def trace_policy(%Policy{} = p, %Context{} = ctx, opts \\ []) do
    source = Keyword.get(opts, :source, :global)

    cond do
      not event_matches?(p, ctx) -> {:miss, :event}
      not agent_matches?(p, ctx, source) -> {:miss, :agent_type}
      not action_matches?(p, ctx) -> {:miss, :action}
      not project_matches?(p, ctx) -> {:miss, :project}
      true -> specialized_trace(p, ctx, opts)
    end
  end

  # Matches a full evaluation candidate (with source metadata).
  defp candidate_matches?(%{policy: policy, source: source}, %Context{} = ctx) do
    trace_policy(policy, ctx, source: source) == :ok
  end

  # System policies with `builtin_matcher` bypass declarative resource_glob
  # and ConditionEval — they own their match logic in an Elixir module.
  defp specialized_trace(%Policy{builtin_matcher: key} = p, %Context{} = ctx, opts)
       when is_binary(key) do
    if Keyword.get(opts, :skip_builtins, false) do
      :ok
    else
      case EyeInTheSky.IAM.BuiltinMatcher.Registry.fetch(key) do
        {:ok, module} ->
          case safe_builtin_trace(module, p, ctx) do
            :match -> :ok
            :no_match -> {:miss, :builtin_matcher}
            :error -> {:miss, :builtin_error}
          end

        :error ->
          :telemetry.execute(
            [:eye_in_the_sky, :iam, :builtin_matcher, :unknown_key],
            %{count: 1},
            %{policy_id: p.id, key: key}
          )

          {:miss, :builtin_matcher}
      end
    end
  end

  defp specialized_trace(%Policy{} = p, %Context{} = ctx, _opts) do
    cond do
      not resource_matches?(p, ctx) -> {:miss, :resource}
      not ConditionEval.matches?(p.condition, ctx, p.id) -> {:miss, :condition}
      true -> :ok
    end
  end

  defp safe_builtin_trace(module, %Policy{} = p, %Context{} = ctx) do
    if module.matches?(p, ctx), do: :match, else: :no_match
  rescue
    e ->
      :telemetry.execute(
        [:eye_in_the_sky, :iam, :builtin_matcher, :error],
        %{count: 1},
        %{policy_id: p.id, module: module, kind: :error, reason: Exception.message(e)}
      )

      :error
  catch
    kind, reason ->
      :telemetry.execute(
        [:eye_in_the_sky, :iam, :builtin_matcher, :error],
        %{count: 1},
        %{policy_id: p.id, module: module, kind: kind, reason: inspect(reason)}
      )

      :error
  end

  defp event_matches?(%Policy{event: nil}, _ctx), do: true
  defp event_matches?(%Policy{event: pe}, %Context{event: ce}), do: pe == ctx_event_name(ce)

  defp ctx_event_name(:pre_tool_use), do: "PreToolUse"
  defp ctx_event_name(:post_tool_use), do: "PostToolUse"
  defp ctx_event_name(:stop), do: "Stop"
  defp ctx_event_name(:user_prompt_submit), do: "UserPromptSubmit"
  defp ctx_event_name(_), do: nil

  # Document-sourced: the document attachment IS the agent-type scope.
  # Policy-level agent_type is bypassed entirely (per spec Decision 1).
  defp agent_matches?(_policy, _ctx, {:document, _, _, _}), do: true
  # Global: existing behavior — wildcard or exact match.
  defp agent_matches?(%Policy{agent_type: "*"}, _ctx, :global), do: true
  defp agent_matches?(%Policy{agent_type: at}, %Context{agent_type: at}, :global), do: true
  defp agent_matches?(_, _, :global), do: false

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

  # Operates on evaluation candidates (%{policy, source}).
  defp partition_by_effect(candidates) do
    Enum.reduce(candidates, {[], [], []}, fn %{policy: p} = candidate, {d, a, i} ->
      case p.effect do
        "deny" -> {[candidate | d], a, i}
        "allow" -> {d, [candidate | a], i}
        "instruct" -> {d, a, [candidate | i]}
        _ -> {d, a, i}
      end
    end)
  end

  defp resolve_permission([_ | _] = denies, _allows, _fallback) do
    best = Enum.min_by(denies, &rank/1)
    {:deny, best.policy, best.source, false}
  end

  defp resolve_permission([], [_ | _] = allows, _fallback) do
    best = Enum.min_by(allows, &rank/1)
    {:allow, best.policy, best.source, false}
  end

  defp resolve_permission([], [], fallback) do
    {fallback, nil, nil, true}
  end

  # Rank tuple: lower is better.
  # - `-priority` sorts high priority first
  # - `id` sorts lower id first as the policy-level tie-break
  # - `source_rank` prefers :global over document when the same policy id matches from both
  defp rank(%{policy: %Policy{priority: priority, id: id}, source: source}) do
    {-priority, id || 0, source_rank(source)}
  end

  defp source_rank(:global), do: 0
  defp source_rank({:document, _, _, _}), do: 1

  defp instruct_message(%Policy{builtin_matcher: key} = p, ctx) when is_binary(key) do
    with {:ok, mod} <- EyeInTheSky.IAM.BuiltinMatcher.Registry.fetch(key),
         true <- function_exported?(mod, :instruction_message, 2),
         msg when is_binary(msg) <- mod.instruction_message(p, ctx) do
      msg
    else
      _ -> message_for(p)
    end
  end

  defp instruct_message(p, _ctx), do: message_for(p)

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
