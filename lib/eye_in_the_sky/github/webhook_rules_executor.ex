defmodule EyeInTheSky.Github.WebhookRulesExecutor do
  require Logger

  alias EyeInTheSky.Github.WebhookRules
  alias EyeInTheSky.Github.RuleActions

  def run(ctx) do
    rules = WebhookRules.matching_rules(ctx.event_type, ctx.repository_full_name)
    Enum.each(rules, &execute_rule(&1, ctx))
    :ok
  end

  defp execute_rule(rule, ctx) do
    case evaluate_guards(rule, ctx) do
      :pass ->
        result = RuleActions.dispatch(rule, ctx)
        status = if result == :ok, do: "ok", else: "failed"
        error = if match?({:error, _}, result), do: elem(result, 1), else: nil

        WebhookRules.record_execution(%{
          rule_id: rule.id,
          delivery_id: ctx.delivery_id,
          repository_full_name: ctx.repository_full_name,
          pr_number: ctx.pr_number,
          status: status,
          error_message: error
        })

      {:skip, reason} ->
        WebhookRules.record_execution(%{
          rule_id: rule.id,
          delivery_id: ctx.delivery_id,
          repository_full_name: ctx.repository_full_name,
          pr_number: ctx.pr_number,
          status: "skipped",
          error_message: reason
        })
    end
  end

  defp evaluate_guards(rule, ctx) do
    guards = rule.guard_config || %{}

    cond do
      guards["ignore_drafts"] == true and ctx.draft? ->
        {:skip, "draft PR"}

      guards["only_if_label"] != nil and
          guards["only_if_label"] not in (ctx.labels || []) ->
        {:skip, "label not present"}

      guards["once_per_pr"] == true and ctx.pr_number != nil and
          WebhookRules.has_ok_execution?(rule.id, ctx.repository_full_name, ctx.pr_number) ->
        {:skip, "once_per_pr: already executed ok"}

      guards["max_runs_per_pr"] != nil and ctx.pr_number != nil and
          WebhookRules.ok_execution_count(rule.id, ctx.repository_full_name, ctx.pr_number) >=
            guards["max_runs_per_pr"] ->
        {:skip, "max_runs_per_pr exceeded"}

      true ->
        :pass
    end
  end
end
