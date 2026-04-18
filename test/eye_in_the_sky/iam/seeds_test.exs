defmodule EyeInTheSky.IAM.SeedsTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.Seeds

  test "all seed policies have required fields" do
    Enum.each(Seeds.policies(), fn attrs ->
      assert is_binary(attrs[:system_key]), "missing system_key in #{inspect(attrs)}"
      assert is_binary(attrs[:name]), "missing name in #{inspect(attrs)}"
      assert is_binary(attrs[:effect]), "missing effect in #{inspect(attrs)}"
      assert attrs[:effect] in ["allow", "deny", "instruct"], "invalid effect in #{inspect(attrs)}"
    end)
  end

  test "workflow_business_hours_only seed exists with correct config" do
    policies = Seeds.policies()
    bhours = Enum.find(policies, &(&1[:system_key] == "builtin.workflow_business_hours_only"))

    assert bhours, "workflow_business_hours_only seed not found"
    assert bhours[:effect] == "deny"
    assert bhours[:event] == "PreToolUse"
    assert bhours[:action] == "*"
    assert bhours[:builtin_matcher] == "workflow_business_hours_only"
    assert bhours[:enabled] == false
    assert is_map(bhours[:condition])
    assert bhours[:condition]["time_between"] == ["09:00", "17:00"]
  end

  test "workflow_stop_gate seed exists with correct config" do
    policies = Seeds.policies()
    stop_gate = Enum.find(policies, &(&1[:system_key] == "builtin.workflow_stop_gate"))

    assert stop_gate, "workflow_stop_gate seed not found"
    assert stop_gate[:effect] == "instruct"
    assert stop_gate[:event] == "Stop"
    assert stop_gate[:action] == "*"
    assert stop_gate[:enabled] == false
  end

  test "Seeds.run is idempotent" do
    Seeds.run()

    {:ok, bhours1} = IAM.get_by_system_key("builtin.workflow_business_hours_only")
    {:ok, stop_gate1} = IAM.get_by_system_key("builtin.workflow_stop_gate")

    Seeds.run()

    {:ok, bhours2} = IAM.get_by_system_key("builtin.workflow_business_hours_only")
    {:ok, stop_gate2} = IAM.get_by_system_key("builtin.workflow_stop_gate")

    assert bhours1.id == bhours2.id
    assert stop_gate1.id == stop_gate2.id
  end

  test "workflow_business_hours_only can be enabled and disabled" do
    Seeds.run()
    {:ok, policy} = IAM.get_by_system_key("builtin.workflow_business_hours_only")

    assert policy.enabled == false

    {:ok, _} = IAM.update_policy(policy, %{"enabled" => true})
    {:ok, updated} = IAM.get_policy(policy.id)

    assert updated.enabled == true
  end

  test "workflow_business_hours_only priority can be edited" do
    Seeds.run()
    {:ok, policy} = IAM.get_by_system_key("builtin.workflow_business_hours_only")

    assert policy.priority == 50

    {:ok, _} = IAM.update_policy(policy, %{"priority" => 75})
    {:ok, updated} = IAM.get_policy(policy.id)

    assert updated.priority == 75
  end

  test "workflow_business_hours_only locked fields cannot be changed" do
    Seeds.run()
    {:ok, policy} = IAM.get_by_system_key("builtin.workflow_business_hours_only")

    # Try to change a locked field (action)
    {:error, cs} = IAM.update_policy(policy, %{"action" => "Bash"})
    refute cs.valid?
    assert "action" in Enum.map(cs.errors, &elem(&1, 0))
  end

  test "builtin_matcher registry contains workflow_business_hours_only" do
    registry_keys = EyeInTheSky.IAM.BuiltinMatcher.Registry.keys()
    assert "workflow_business_hours_only" in registry_keys
  end

  test "workflow_business_hours_only matches via builtin registry" do
    {:ok, module} = EyeInTheSky.IAM.BuiltinMatcher.Registry.fetch("workflow_business_hours_only")
    assert module == EyeInTheSky.IAM.Builtin.WorkflowBusinessHoursOnly
    assert function_exported?(module, :matches?, 2)
  end
end
