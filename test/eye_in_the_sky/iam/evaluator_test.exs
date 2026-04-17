defmodule EyeInTheSky.IAM.EvaluatorTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Decision
  alias EyeInTheSky.IAM.Evaluator
  alias EyeInTheSky.IAM.Policy

  defp pol(attrs) do
    base = %Policy{
      id: :rand.uniform(1_000_000),
      name: "p",
      effect: "allow",
      agent_type: "*",
      project_id: nil,
      project_path: "*",
      action: "*",
      resource_glob: nil,
      condition: %{},
      priority: 0,
      enabled: true,
      message: nil,
      editable_fields: []
    }

    struct(base, attrs)
  end

  defp ctx(attrs \\ []) do
    struct(
      %Context{
        event: :pre_tool_use,
        agent_type: "root",
        project_id: 1,
        project_path: "/p",
        tool: "Bash",
        resource_type: :command,
        resource_path: "/p/x",
        metadata: %{}
      },
      attrs
    )
  end

  test "empty policy list falls back to :allow by default" do
    %Decision{permission: :allow, default?: true, winning_policy: nil, evaluated_count: 0} =
      Evaluator.decide(ctx(), policies: [])
  end

  test "fallback_permission: :deny flips fallback" do
    %Decision{permission: :deny, default?: true} =
      Evaluator.decide(ctx(), policies: [], fallback_permission: :deny)
  end

  test "allow policy wins when no deny matches" do
    policies = [pol(effect: "allow", action: "Bash", name: "a1")]

    %Decision{permission: :allow, default?: false, winning_policy: %Policy{name: "a1"}} =
      Evaluator.decide(ctx(), policies: policies)
  end

  test "deny beats allow regardless of priority" do
    policies = [
      pol(effect: "allow", priority: 100, name: "allow-high"),
      pol(effect: "deny", priority: 0, name: "deny-low")
    ]

    %Decision{permission: :deny, winning_policy: %Policy{name: "deny-low"}} =
      Evaluator.decide(ctx(), policies: policies)
  end

  test "higher priority wins within same effect class" do
    policies = [
      pol(effect: "allow", priority: 1, name: "low"),
      pol(effect: "allow", priority: 10, name: "high")
    ]

    %Decision{winning_policy: %Policy{name: "high"}} =
      Evaluator.decide(ctx(), policies: policies)
  end

  test "id breaks ties when priority equal" do
    policies = [
      pol(id: 99, effect: "deny", priority: 5, name: "later"),
      pol(id: 1, effect: "deny", priority: 5, name: "earlier")
    ]

    %Decision{winning_policy: %Policy{name: "earlier"}} =
      Evaluator.decide(ctx(), policies: policies)
  end

  test "agent_type mismatch excludes policy" do
    policies = [pol(effect: "deny", agent_type: "other", name: "nope")]

    %Decision{permission: :allow, default?: true} =
      Evaluator.decide(ctx(agent_type: "root"), policies: policies)
  end

  test "action literal must match tool" do
    policies = [pol(effect: "deny", action: "Write", name: "w")]

    %Decision{permission: :allow, default?: true} =
      Evaluator.decide(ctx(tool: "Bash"), policies: policies)
  end

  test "project_id takes precedence over project_path" do
    policies = [
      pol(effect: "deny", project_id: 999, project_path: "/p", name: "by-id")
    ]

    # ctx project_id=1 != 999 → doesn't match
    %Decision{permission: :allow, default?: true} =
      Evaluator.decide(ctx(), policies: policies)
  end

  test "project_path glob matches when project_id nil" do
    policies = [pol(effect: "deny", project_id: nil, project_path: "/p", name: "path")]

    %Decision{permission: :deny} = Evaluator.decide(ctx(), policies: policies)
  end

  test "resource_glob filters matches" do
    policies = [pol(effect: "deny", resource_glob: "/other/*", name: "off")]

    %Decision{permission: :allow, default?: true} = Evaluator.decide(ctx(), policies: policies)
  end

  test "instructions always attach, even on fallback" do
    policies = [pol(effect: "instruct", message: "hey", name: "i1")]

    %Decision{permission: :allow, default?: true, instructions: [%{message: "hey"}]} =
      Evaluator.decide(ctx(), policies: policies)
  end

  test "instructions attach alongside deny" do
    policies = [
      pol(effect: "deny", name: "d1", message: "blocked"),
      pol(effect: "instruct", name: "i1", message: "fyi")
    ]

    %Decision{
      permission: :deny,
      reason: "blocked",
      instructions: [%{message: "fyi"}]
    } = Evaluator.decide(ctx(), policies: policies)
  end

  test "condition gates matching" do
    policies = [
      pol(
        effect: "deny",
        condition: %{"session_state_equals" => "working"},
        name: "gated"
      )
    ]

    %Decision{permission: :allow, default?: true} =
      Evaluator.decide(ctx(metadata: %{"session_state" => "stopped"}), policies: policies)

    %Decision{permission: :deny} =
      Evaluator.decide(ctx(metadata: %{"session_state" => "working"}), policies: policies)
  end

  test "reason falls back to '<effect>: <name>' when message nil" do
    policies = [pol(effect: "deny", name: "no-msg", message: nil)]

    %Decision{reason: "deny: no-msg"} = Evaluator.decide(ctx(), policies: policies)
  end
end
