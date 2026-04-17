defmodule EyeInTheSky.IAM.ConditionEval do
  @moduledoc """
  Runtime evaluator for IAM condition JSONB predicates.

  V1 supports exactly three predicates:

    * `"time_between"` — `["HH:MM", "HH:MM"]`, wall-clock window in UTC.
    * `"env_equals"`   — map of `ENV_VAR => expected_string`; all must match.
    * `"session_state_equals"` — string; compared against ctx.metadata["session_state"].

  Write-time validation lives in `EyeInTheSky.IAM.Policy`; this module assumes
  structures are well-formed but defends against any that slip through (eg.
  older rows). On any evaluation error the condition is treated as
  non-matching and a telemetry event is emitted.
  """

  alias EyeInTheSky.IAM.Context

  @telemetry_error [:eye_in_the_sky, :iam, :condition, :error]

  @doc """
  `true` when every entry in `condition` holds for the given context. An
  empty/absent condition map always matches.
  """
  @spec matches?(map() | nil, Context.t(), integer() | nil) :: boolean()
  def matches?(nil, _ctx, _pid), do: true
  def matches?(cond_map, _ctx, _pid) when map_size(cond_map) == 0, do: true

  def matches?(cond_map, %Context{} = ctx, policy_id) when is_map(cond_map) do
    Enum.all?(cond_map, fn {key, value} ->
      evaluate(to_string(key), value, ctx, policy_id)
    end)
  end

  def matches?(_, _, _), do: false

  # ── predicate evaluators ────────────────────────────────────────────────────

  defp evaluate("time_between", [from, to], _ctx, policy_id) do
    with {:ok, {fh, fm}} <- parse_hhmm(from),
         {:ok, {th, tm}} <- parse_hhmm(to) do
      now = now_utc()
      in_window?(now, {fh, fm}, {th, tm})
    else
      _ ->
        emit_error(policy_id, "time_between", {:invalid_format, [from, to]})
        false
    end
  end

  defp evaluate("env_equals", %{} = expected, _ctx, policy_id) do
    Enum.all?(expected, fn
      {k, v} when is_binary(k) and is_binary(v) ->
        System.get_env(k) == v

      {k, v} ->
        emit_error(policy_id, "env_equals", {:invalid_entry, {k, v}})
        false
    end)
  end

  defp evaluate("session_state_equals", value, %Context{metadata: meta}, _policy_id)
       when is_binary(value) do
    (meta[:session_state] || meta["session_state"]) == value
  end

  defp evaluate(key, value, _ctx, policy_id) do
    emit_error(policy_id, key, {:unknown_predicate, value})
    false
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp parse_hhmm(str) when is_binary(str) do
    case Regex.run(~r/\A([01]\d|2[0-3]):([0-5]\d)\z/, str) do
      [_, h, m] -> {:ok, {String.to_integer(h), String.to_integer(m)}}
      _ -> :error
    end
  end

  defp parse_hhmm(_), do: :error

  defp now_utc do
    %DateTime{hour: h, minute: m} = DateTime.utc_now()
    {h, m}
  end

  defp in_window?({h, m}, {fh, fm}, {th, tm}) do
    cur = h * 60 + m
    from = fh * 60 + fm
    to = th * 60 + tm

    if from <= to do
      cur >= from and cur <= to
    else
      # Window wraps midnight (e.g. 22:00 -> 06:00).
      cur >= from or cur <= to
    end
  end

  defp emit_error(policy_id, predicate, reason) do
    :telemetry.execute(
      @telemetry_error,
      %{count: 1},
      %{policy_id: policy_id, predicate: predicate, reason: reason}
    )
  end
end
