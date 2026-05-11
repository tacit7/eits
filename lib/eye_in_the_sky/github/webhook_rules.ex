defmodule EyeInTheSky.Github.WebhookRules do
  import Ecto.Query

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Github.WebhookRule
  alias EyeInTheSky.Github.WebhookRuleExecution

  def create(attrs) do
    %WebhookRule{}
    |> WebhookRule.changeset(attrs)
    |> Repo.insert()
  end

  def update(rule, attrs) do
    rule
    |> WebhookRule.changeset(attrs)
    |> Repo.update()
  end

  def list, do: Repo.all(from r in WebhookRule, order_by: [asc: r.priority, asc: r.id])

  def matching_rules(event_type, repository_full_name) do
    Repo.all(
      from r in WebhookRule,
        where: r.enabled == true,
        where: r.event_type == ^event_type or r.event_type == "*",
        where:
          is_nil(r.repository_full_name) or
            r.repository_full_name == ^(repository_full_name || ""),
        order_by: [asc: r.priority, asc: r.id]
    )
  end

  def record_execution(attrs) do
    %WebhookRuleExecution{}
    |> WebhookRuleExecution.changeset(attrs)
    |> Repo.insert()
  end

  def ok_execution_count(rule_id, repo, pr_number) do
    Repo.aggregate(
      from(e in WebhookRuleExecution,
        where:
          e.rule_id == ^rule_id and e.repository_full_name == ^repo and
            e.pr_number == ^pr_number and e.status == "ok"
      ),
      :count
    )
  end

  def has_ok_execution?(rule_id, repo, pr_number) do
    ok_execution_count(rule_id, repo, pr_number) > 0
  end
end
