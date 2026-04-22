defmodule EyeInTheSkyWeb.Api.V1.IAMController do
  use EyeInTheSkyWeb, :controller

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.Evaluator
  alias EyeInTheSky.IAM.HookResponse
  alias EyeInTheSky.IAM.Normalizer

  @doc """
  POST /api/v1/iam/decide

  Accepts a raw Claude Code hook payload, evaluates it against the IAM policy
  engine, and returns the hook-protocol JSON response that Claude Code expects.

  On malformed payload (not a JSON object), returns 400.
  """
  def decide(conn, params) when is_map(params) do
    start_us = System.monotonic_time(:microsecond)

    ctx = Normalizer.from_hook_payload(params)
    decision = Evaluator.decide(ctx)

    duration_us = System.monotonic_time(:microsecond) - start_us
    hook_json = HookResponse.from_decision(decision, ctx.event)

    IAM.record_audit(ctx, decision, params, duration_us)

    json(conn, hook_json)
  end
end
