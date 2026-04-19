defmodule EyeInTheSky.IAM.PolicyTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.Policy

  describe "create_changeset/2" do
    test "requires name and effect" do
      cs = Policy.create_changeset(%{})
      refute cs.valid?
      assert %{name: _, effect: _} = errors_on(cs)
    end

    test "accepts a minimal valid policy" do
      cs = Policy.create_changeset(%{name: "x", effect: "allow"})
      assert cs.valid?
    end

    test "rejects unknown effect" do
      cs = Policy.create_changeset(%{name: "x", effect: "maybe"})
      refute cs.valid?
      assert %{effect: _} = errors_on(cs)
    end

    test "rejects unsupported condition predicate" do
      cs =
        Policy.create_changeset(%{
          name: "x",
          effect: "allow",
          condition: %{"whatever" => true}
        })

      refute cs.valid?
      assert %{condition: _} = errors_on(cs)
    end

    test "validates time_between shape" do
      bad =
        Policy.create_changeset(%{
          name: "x",
          effect: "allow",
          condition: %{"time_between" => ["25:00", "17:00"]}
        })

      refute bad.valid?

      good =
        Policy.create_changeset(%{
          name: "x",
          effect: "allow",
          condition: %{"time_between" => ["09:00", "17:00"]}
        })

      assert good.valid?
    end

    test "validates env_equals shape" do
      bad =
        Policy.create_changeset(%{
          name: "x",
          effect: "allow",
          condition: %{"env_equals" => %{"FOO" => 1}}
        })

      refute bad.valid?

      good =
        Policy.create_changeset(%{
          name: "x",
          effect: "allow",
          condition: %{"env_equals" => %{"FOO" => "bar"}}
        })

      assert good.valid?
    end

    test "rejects empty-string project_path" do
      cs = Policy.create_changeset(%{name: "x", effect: "allow", project_path: ""})
      refute cs.valid?
      assert %{project_path: _} = errors_on(cs)
    end

    test "accepts wildcard project_path" do
      cs = Policy.create_changeset(%{name: "x", effect: "allow", project_path: "*"})
      assert cs.valid?
    end
  end

  describe "update_changeset/2 locked-field enforcement" do
    test "allows editing whitelisted fields on system policies" do
      {:ok, policy} =
        IAM.create_policy(%{
          name: "System",
          effect: "deny",
          system_key: "t_block_test_#{System.unique_integer([:positive])}",
          editable_fields: ["enabled", "priority", "message"]
        })

      cs = Policy.update_changeset(policy, %{"priority" => 100, "message" => "new msg"})
      assert cs.valid?
    end

    test "blocks editing locked matcher fields on system policies" do
      {:ok, policy} =
        IAM.create_policy(%{
          name: "System",
          effect: "deny",
          system_key: "t_block_matcher_#{System.unique_integer([:positive])}",
          editable_fields: ["enabled", "priority", "message"]
        })

      cs = Policy.update_changeset(policy, %{"agent_type" => "code-reviewer"})
      refute cs.valid?
      assert %{agent_type: _} = errors_on(cs)
    end

    test "user policies (no system_key) permit all fields" do
      {:ok, policy} = IAM.create_policy(%{name: "User", effect: "allow"})

      cs =
        Policy.update_changeset(policy, %{
          "agent_type" => "code-reviewer",
          "priority" => 50
        })

      assert cs.valid?
    end
  end
end
