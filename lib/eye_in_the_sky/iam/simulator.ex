defmodule EyeInTheSky.IAM.Simulator do
  @moduledoc """
  Dry-run simulator for the IAM policy engine.

  Given a hypothetical `EyeInTheSky.IAM.Context`, this module evaluates every
  enabled policy (from the cache, or an explicit list) using the same matching
  pipeline as `EyeInTheSky.IAM.Evaluator`, and returns a structured trace:

    * the final `Decision`,
    * a per-candidate trace entry with match/miss-reason and source,
    * the winning policy id (if any),
    * whether the decision fell back to the default permission,
    * document contributions (which documents contributed matching policies).

  The simulator shares matching code with the evaluator via
  `EyeInTheSky.IAM.Evaluator.trace_policy/3` — no logic is duplicated.

  ## Source metadata

  Each trace entry includes a `:source` field (`EvaluationSource.t()`).
  Use `EvaluationSource.label/1` to render it — never match on the raw tuple.

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
  alias EyeInTheSky.IAM.EvaluationSource
  alias EyeInTheSky.IAM.Evaluator
  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSky.IAM.PolicyCache

  # PolicyCache.for_agent_type/1 is added by the document-cache parallel agent.
  # Suppress the undefined-function warning so this branch compiles cleanly
  # before the two feature branches are merged.
  @compile {:no_warn_undefined, {EyeInTheSky.IAM.PolicyCache, :for_agent_type, 1}}

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
          source: EvaluationSource.t(),
          matched?: boolean(),
          reason: :ok | {:miss, miss_reason()}
        }

  @type document_contribution :: %{
          document_id: integer(),
          document_name: String.t(),
          agent_type: String.t(),
          effective_policy_count: integer()
        }

  @type result :: %{
          decision: Decision.t(),
          traces: [trace_entry()],
          winner_id: integer() | nil,
          fallback?: boolean(),
          document_contributions: [document_contribution()]
        }

  @type opts :: [
          fallback_permission: :allow | :deny,
          policies: [Policy.t()],
          document_candidates: [map()],
          include_disabled: boolean(),
          skip_builtins: boolean()
        ]

  @doc """
  Run a simulation. Returns a full trace — see module doc.

  Options:

    * `:fallback_permission` — `:allow` (default) or `:deny`.
    * `:policies` — explicit global policy list. If omitted, uses the cache via
      `PolicyCache.all_enabled/0`.
    * `:document_candidates` — explicit document candidate list (maps with
      `:policy`, `:document`, `:attached_agent_type`), bypassing
      `PolicyCache.for_agent_type/1`.
    * `:include_disabled` — include disabled policies in the trace, marked
      with `{:miss, :disabled}`. Has no effect when `:policies` is passed.
      Default `false`.
    * `:skip_builtins` — bypass built-in matcher dispatch. Default `false`.
  """
  @spec simulate(Context.t(), opts()) :: result()
  def simulate(%Context{} = ctx, opts \\ []) do
    fallback = Keyword.get(opts, :fallback_permission, :allow)
    skip_builtins = Keyword.get(opts, :skip_builtins, false)

    global_policies = load_global_policies(opts)

    doc_candidates_raw =
      case Keyword.fetch(opts, :document_candidates) do
        {:ok, list} ->
          list

        :error ->
          if is_binary(ctx.agent_type) and ctx.agent_type not in ["", "*"] do
            PolicyCache.for_agent_type(ctx.agent_type)
          else
            []
          end
      end

    global_candidates = Enum.map(global_policies, &%{policy: &1, source: :global})

    document_candidates =
      Enum.map(doc_candidates_raw, fn %{policy: p, document: doc, attached_agent_type: at} ->
        %{policy: p, source: {:document, doc.id, doc.name, at}}
      end)

    all_candidates = global_candidates ++ document_candidates

    traces =
      Enum.map(all_candidates, fn %{policy: p, source: src} ->
        if p.enabled do
          reason = Evaluator.trace_policy(p, ctx, source: src, skip_builtins: skip_builtins)
          %{policy: p, source: src, matched?: reason == :ok, reason: reason}
        else
          %{policy: p, source: src, matched?: false, reason: {:miss, :disabled}}
        end
      end)

    matched_candidates = for t <- traces, t.matched?, do: %{policy: t.policy, source: t.source}

    {denies, allows, instructs} = partition_by_effect(matched_candidates)

    {permission, winner, winner_source, fallback?} = resolve_permission(denies, allows, fallback)

    instructions =
      instructs
      |> Enum.sort_by(&rank/1)
      |> Enum.map(fn %{policy: p, source: src} ->
        %{policy: p, message: message_for(p), source: src}
      end)

    decision = %Decision{
      permission: permission,
      winning_policy: winner,
      winning_source: winner_source,
      reason: winner && message_for(winner),
      instructions: instructions,
      default?: fallback?,
      evaluated_count: length(all_candidates)
    }

    document_contributions = compute_document_contributions(traces)

    :telemetry.execute(
      @telemetry_simulate,
      %{traces: length(traces), matches: length(matched_candidates)},
      %{permission: permission, fallback?: fallback?, skip_builtins: skip_builtins}
    )

    %{
      decision: decision,
      traces: traces,
      winner_id: winner && winner.id,
      fallback?: fallback?,
      document_contributions: document_contributions
    }
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp load_global_policies(opts) do
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

  defp compute_document_contributions(traces) do
    traces
    |> Enum.filter(fn t -> t.matched? and match?({:document, _, _, _}, t.source) end)
    |> Enum.map(fn t ->
      {:document, doc_id, doc_name, at} = t.source
      {doc_id, doc_name, at}
    end)
    |> Enum.uniq()
    |> Enum.map(fn {doc_id, doc_name, at} ->
      count =
        Enum.count(traces, fn t ->
          t.matched? and t.source == {:document, doc_id, doc_name, at}
        end)

      %{
        document_id: doc_id,
        document_name: doc_name,
        agent_type: at,
        effective_policy_count: count
      }
    end)
  end

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

  defp rank(%{policy: %Policy{priority: priority, id: id}, source: source}) do
    {-priority, id || 0, source_rank(source)}
  end

  defp source_rank(:global), do: 0
  defp source_rank({:document, _, _, _}), do: 1

  defp message_for(%Policy{message: nil, name: name, effect: effect}),
    do: "#{effect}: #{name}"

  defp message_for(%Policy{message: msg}), do: msg
end
