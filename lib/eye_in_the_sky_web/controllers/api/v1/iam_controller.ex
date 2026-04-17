defmodule EyeInTheSkyWeb.Api.V1.IAMController do
  use EyeInTheSkyWeb, :controller

  alias EyeInTheSky.IAM.Evaluator
  alias EyeInTheSky.IAM.HookResponse
  alias EyeInTheSky.IAM.Normalizer
  alias EyeInTheSky.Repo

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

    fire_audit(ctx, decision, params, duration_us)

    json(conn, hook_json)
  end

  # ── audit ────────────────────────────────────────────────────────────────────

  defp fire_audit(ctx, decision, raw_payload, duration_us) do
    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      write_audit(ctx, decision, raw_payload, duration_us)
    end)
  end

  defp write_audit(ctx, decision, raw_payload, duration_us) do
    decision_id = Ecto.UUID.dump!(Ecto.UUID.generate())

    session_uuid_bin =
      case ctx.session_uuid do
        nil -> nil
        uuid -> Ecto.UUID.dump!(uuid)
      end

    instructions_snapshot =
      Enum.map(decision.instructions, fn %{policy: p, message: msg} ->
        %{
          "policy_id" => p.id,
          "system_key" => p.system_key,
          "name" => p.name,
          "message" => msg
        }
      end)

    {winning_policy_id, winning_system_key, winning_name} =
      case decision.winning_policy do
        nil -> {nil, nil, nil}
        p -> {p.id, p.system_key, p.name}
      end

    row = %{
      decision_id: decision_id,
      session_uuid: session_uuid_bin,
      event: to_string(ctx.event),
      agent_type: ctx.agent_type,
      project_id: ctx.project_id,
      project_path: ctx.project_path,
      tool: ctx.tool,
      resource_path: ctx.resource_path,
      permission: to_string(decision.permission),
      default: decision.default?,
      winning_policy_id: winning_policy_id,
      winning_policy_system_key: winning_system_key,
      winning_policy_name: winning_name,
      reason: decision.reason,
      instructions_snapshot: instructions_snapshot,
      evaluated_count: decision.evaluated_count,
      duration_us: duration_us,
      raw_payload: raw_payload,
      inserted_at: DateTime.utc_now()
    }

    Repo.insert_all("iam_decisions", [row])
  end
end
