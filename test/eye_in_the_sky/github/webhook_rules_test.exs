defmodule EyeInTheSky.Github.WebhookRulesTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Github.WebhookRules

  @valid_attrs %{
    event_type: "pull_request.opened",
    action_type: "broadcast_only",
    action_config: %{"topic" => "test", "message" => "PR {{pr_number}} opened"},
    guard_config: %{}
  }

  describe "create/1" do
    test "creates a rule with valid attributes" do
      assert {:ok, rule} = WebhookRules.create(@valid_attrs)
      assert rule.event_type == "pull_request.opened"
      assert rule.enabled == true
      assert rule.priority == 100
    end

    test "rejects unknown template variable in action_config" do
      attrs = put_in(@valid_attrs, [:action_config, "message"], "{{secret_token}}")
      assert {:error, changeset} = WebhookRules.create(attrs)
      assert changeset.errors[:action_config]
    end

    test "rejects missing required action_config key for spawn_agent" do
      attrs = %{@valid_attrs | action_type: "spawn_agent", action_config: %{"agent" => "codex"}}
      assert {:error, changeset} = WebhookRules.create(attrs)
      assert changeset.errors[:action_config]
    end

    test "accepts valid spawn_agent config" do
      attrs = %{
        @valid_attrs
        | action_type: "spawn_agent",
          action_config: %{"agent" => "codex", "instructions" => "Review PR {{pr_number}}"}
      }

      assert {:ok, _} = WebhookRules.create(attrs)
    end
  end

  describe "matching_rules/2" do
    test "returns enabled rules matching event_type" do
      {:ok, rule} = WebhookRules.create(@valid_attrs)
      rules = WebhookRules.matching_rules("pull_request.opened", nil)
      assert Enum.any?(rules, &(&1.id == rule.id))
    end

    test "does not return disabled rules" do
      {:ok, rule} = WebhookRules.create(@valid_attrs)
      WebhookRules.update(rule, %{enabled: false})
      rules = WebhookRules.matching_rules("pull_request.opened", nil)
      refute Enum.any?(rules, &(&1.id == rule.id))
    end

    test "wildcard * matches any event_type" do
      {:ok, rule} = WebhookRules.create(%{@valid_attrs | event_type: "*"})
      rules = WebhookRules.matching_rules("push", nil)
      assert Enum.any?(rules, &(&1.id == rule.id))
    end
  end
end
