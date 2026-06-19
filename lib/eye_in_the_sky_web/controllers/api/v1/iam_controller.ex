defmodule EyeInTheSkyWeb.Api.V1.IAMController do
  use EyeInTheSkyWeb, :controller

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.Evaluator
  alias EyeInTheSky.IAM.HookResponse
  alias EyeInTheSky.IAM.Normalizer
  alias EyeInTheSky.Sessions

  @doc """
  POST /api/v1/iam/decide

  Accepts a raw Claude Code hook payload, evaluates it against the IAM policy
  engine, and returns the hook-protocol JSON response that Claude Code expects.

  On malformed payload (not a JSON object), returns 400.
  """
  def decide(conn, params) when is_map(params) do
    start_us = System.monotonic_time(:microsecond)

    params = enrich_agent_type(params)
    ctx = Normalizer.from_hook_payload(params)
    decision = Evaluator.decide(ctx)

    duration_us = System.monotonic_time(:microsecond) - start_us
    hook_json = HookResponse.from_decision(decision, ctx.event)

    IAM.record_audit(ctx, decision, sanitize_payload(params), duration_us)

    json(conn, hook_json)
  end

  # ── private ──────────────────────────────────────────────────────────────────

  @max_content_bytes 4096

  # Strip large resource_content before storing in iam_decisions.raw_payload to
  # prevent file-read output (potentially MBs) from bloating the audit table.
  defp sanitize_payload(params) do
    case Map.get(params, "resource_content") do
      nil ->
        params

      content when is_binary(content) and byte_size(content) > @max_content_bytes ->
        Map.put(params, "resource_content", binary_part(content, 0, @max_content_bytes) <> "…[truncated]")

      _ ->
        params
    end
  end

  # Claude Code hook payloads don't include agent_type. Enrich it from the
  # session record so document-based policies (which scope by agent type) fire
  # correctly. Uses put_new so any explicit agent_type in the payload wins.
  defp enrich_agent_type(params) do
    with nil <- Map.get(params, "agent_type"),
         uuid when is_binary(uuid) <- Map.get(params, "session_id"),
         {:ok, slug} <- Sessions.agent_type_for_session(uuid) do
      Map.put(params, "agent_type", slug)
    else
      _ -> params
    end
  end
end
