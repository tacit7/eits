defmodule EyeInTheSky.Github.WebhookRulesExecutorTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Github.WebhookRulesExecutor
  alias EyeInTheSky.Github.WebhookRules
  alias EyeInTheSky.Github.EventContext

  defp ctx(overrides \\ %{}) do
    Map.merge(
      %EventContext{
        delivery_id: "d1",
        event_type: "pull_request.opened",
        repository_full_name: "tacit7/eits",
        sender_login: "uriel",
        github_pr_id: 1,
        pr_number: 1,
        head_branch: "feature/x",
        base_branch: "main",
        labels: [],
        draft?: false,
        merged?: false
      },
      overrides
    )
  end

  defp broadcast_rule(overrides \\ %{}) do
    WebhookRules.create(
      Map.merge(
        %{
          event_type: "pull_request.opened",
          action_type: "broadcast_only",
          action_config: %{"topic" => "test_topic", "message" => "PR {{pr_number}}"},
          guard_config: %{}
        },
        overrides
      )
    )
    |> elem(1)
  end

  test "executes matching broadcast_only rule and records ok execution" do
    rule = broadcast_rule()
    WebhookRulesExecutor.run(ctx())
    assert WebhookRules.has_ok_execution?(rule.id, "tacit7/eits", 1)
  end

  test "once_per_pr guard skips on second run with ok execution" do
    rule = broadcast_rule(%{guard_config: %{"once_per_pr" => true}})
    WebhookRulesExecutor.run(ctx())
    WebhookRulesExecutor.run(ctx())
    count = WebhookRules.ok_execution_count(rule.id, "tacit7/eits", 1)
    assert count == 1
  end

  test "ignore_drafts guard skips draft PRs" do
    rule = broadcast_rule(%{guard_config: %{"ignore_drafts" => true}})
    WebhookRulesExecutor.run(ctx(%{draft?: true}))
    refute WebhookRules.has_ok_execution?(rule.id, "tacit7/eits", 1)
  end

  test "only_if_label guard skips when label absent" do
    rule = broadcast_rule(%{guard_config: %{"only_if_label" => "agent-review"}})
    WebhookRulesExecutor.run(ctx(%{labels: []}))
    refute WebhookRules.has_ok_execution?(rule.id, "tacit7/eits", 1)
  end

  test "only_if_label guard fires when label present" do
    rule = broadcast_rule(%{guard_config: %{"only_if_label" => "agent-review"}})
    WebhookRulesExecutor.run(ctx(%{labels: ["agent-review"]}))
    assert WebhookRules.has_ok_execution?(rule.id, "tacit7/eits", 1)
  end

  test "once_per_pr does NOT skip when previous execution was skipped" do
    rule = broadcast_rule(%{guard_config: %{"once_per_pr" => true, "ignore_drafts" => true}})
    WebhookRulesExecutor.run(ctx(%{draft?: true}))
    WebhookRulesExecutor.run(ctx(%{draft?: false}))
    assert WebhookRules.has_ok_execution?(rule.id, "tacit7/eits", 1)
  end

  test "broadcast_only does not raise" do
    broadcast_rule()
    assert :ok = WebhookRulesExecutor.run(ctx())
  end
end
