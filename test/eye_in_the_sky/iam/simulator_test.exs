defmodule EyeInTheSky.IAM.SimulatorTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Decision
  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSky.IAM.Simulator

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
        resource_content: "ls -la",
        metadata: %{}
      },
      attrs
    )
  end

  describe "simulate/2 — core outcomes" do
    test "empty list falls back to :allow and flags default" do
      result = Simulator.simulate(ctx(), policies: [])

      assert %Decision{permission: :allow, default?: true, evaluated_count: 0} = result.decision
      assert result.traces == []
      assert result.winner_id == nil
      assert result.fallback? == true
    end

    test "fallback_permission :deny flips the default branch" do
      result = Simulator.simulate(ctx(), policies: [], fallback_permission: :deny)
      assert result.decision.permission == :deny
      assert result.fallback? == true
    end

    test "allow policy produces allow decision and winner" do
      p = pol(effect: "allow", action: "Bash", name: "allow-bash", id: 42)
      result = Simulator.simulate(ctx(), policies: [p])

      assert result.decision.permission == :allow
      assert result.fallback? == false
      assert result.winner_id == 42
      assert [%{matched?: true, reason: :ok}] = result.traces
    end

    test "deny beats allow regardless of priority" do
      allow = pol(effect: "allow", priority: 100, name: "allow-high", id: 1)
      deny = pol(effect: "deny", priority: 0, name: "deny-low", id: 2)

      result = Simulator.simulate(ctx(), policies: [allow, deny])

      assert result.decision.permission == :deny
      assert result.winner_id == 2
    end

    test "instruct policies accumulate without changing permission" do
      instruct = pol(effect: "instruct", name: "advise", id: 7, message: "be careful")
      result = Simulator.simulate(ctx(), policies: [instruct])

      assert result.decision.permission == :allow
      assert result.fallback? == true
      assert [%{message: "be careful", policy: %Policy{id: 7}}] = result.decision.instructions
    end
  end

  describe "simulate/2 — miss-reason annotation" do
    test "agent_type mismatch" do
      p = pol(agent_type: "specialist", name: "agent-specific")
      [trace] = Simulator.simulate(ctx(agent_type: "root"), policies: [p]).traces

      assert trace.matched? == false
      assert trace.reason == {:miss, :agent_type}
    end

    test "action mismatch" do
      p = pol(action: "Edit", name: "edit-only")
      [trace] = Simulator.simulate(ctx(tool: "Bash"), policies: [p]).traces
      assert trace.reason == {:miss, :action}
    end

    test "project mismatch" do
      p = pol(project_id: 999, name: "other-project")
      [trace] = Simulator.simulate(ctx(project_id: 1), policies: [p]).traces
      assert trace.reason == {:miss, :project}
    end

    test "resource glob mismatch" do
      p = pol(resource_glob: "/secret/**", name: "secret-only")
      [trace] = Simulator.simulate(ctx(resource_path: "/p/x.txt"), policies: [p]).traces
      assert trace.reason == {:miss, :resource}
    end

    test "condition mismatch" do
      p = pol(condition: %{"env_equals" => %{"MODE" => "prod"}}, name: "prod-only")
      context = ctx() |> Map.put(:metadata, %{env: %{"MODE" => "dev"}})
      [trace] = Simulator.simulate(context, policies: [p]).traces
      assert trace.reason == {:miss, :condition}
    end

    test "disabled policies included when :include_disabled not used get reason ok or miss" do
      # With explicit :policies, disabled flag is honored by the simulator itself.
      p = pol(enabled: false, effect: "allow", action: "Bash")
      [trace] = Simulator.simulate(ctx(), policies: [p]).traces
      assert trace.matched? == false
      assert trace.reason == {:miss, :disabled}
    end
  end

  describe "simulate/2 — built-in matchers" do
    defp builtin_pol(attrs) do
      pol(
        Keyword.merge(
          [
            system_key: "test.key",
            builtin_matcher: "block_rm_rf",
            effect: "deny",
            action: "Bash",
            agent_type: "*"
          ],
          attrs
        )
      )
    end

    test "built-in dispatch runs normally and matches dangerous rm -rf" do
      p = builtin_pol(name: "rm-rf")
      context = ctx(resource_content: "rm -rf /")

      result = Simulator.simulate(context, policies: [p])

      assert result.decision.permission == :deny
      assert [%{matched?: true, reason: :ok}] = result.traces
    end

    test "built-in dispatch reports :builtin_matcher miss for benign input" do
      p = builtin_pol(name: "rm-rf")
      context = ctx(resource_content: "ls -la")

      [trace] = Simulator.simulate(context, policies: [p]).traces

      assert trace.matched? == false
      assert trace.reason == {:miss, :builtin_matcher}
    end

    test "skip_builtins bypasses dispatch — built-in policy matches on coarse axes" do
      p = builtin_pol(name: "rm-rf")
      # Benign content; without skip this would miss. With skip, it matches.
      context = ctx(resource_content: "ls -la")

      result = Simulator.simulate(context, policies: [p], skip_builtins: true)

      assert result.decision.permission == :deny
      assert [%{matched?: true, reason: :ok}] = result.traces
    end

    test "unknown builtin_matcher key reports :builtin_matcher miss" do
      p = builtin_pol(name: "ghost", builtin_matcher: "does_not_exist")
      [trace] = Simulator.simulate(ctx(), policies: [p]).traces
      assert trace.reason == {:miss, :builtin_matcher}
    end
  end

  describe "simulate/2 — result shape" do
    test "winner_id is nil on fallback" do
      result = Simulator.simulate(ctx(), policies: [])
      assert result.winner_id == nil
      assert result.fallback? == true
    end

    test "evaluated_count reflects traced policies" do
      policies = [pol(action: "Edit"), pol(action: "Bash", effect: "allow")]
      result = Simulator.simulate(ctx(tool: "Bash"), policies: policies)
      assert result.decision.evaluated_count == 2
      assert length(result.traces) == 2
    end
  end
end
