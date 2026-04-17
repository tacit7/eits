defmodule EyeInTheSky.IAMTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.Policy

  describe "create_policy/1" do
    test "creates a user policy" do
      {:ok, %Policy{} = p} = IAM.create_policy(%{name: "User rule", effect: "allow"})
      assert p.id
      assert p.system_key == nil
      assert p.enabled == true
    end

    test "rejects invalid effect" do
      assert {:error, cs} = IAM.create_policy(%{name: "bad", effect: "maybe"})
      refute cs.valid?
    end
  end

  describe "get_policy/1 and get_by_system_key/1" do
    test "round-trips a system policy" do
      sk = "t_ident_#{System.unique_integer([:positive])}"

      {:ok, p} =
        IAM.create_policy(%{
          name: "Sys",
          effect: "deny",
          system_key: sk,
          editable_fields: ["enabled"]
        })

      assert {:ok, ^p} = IAM.get_policy(p.id)
      assert {:ok, ^p} = IAM.get_by_system_key(sk)
    end

    test "returns :not_found for missing ids" do
      assert {:error, :not_found} = IAM.get_policy(-1)
      assert {:error, :not_found} = IAM.get_by_system_key("nope")
    end
  end

  describe "seed_builtin/1 (seed-once semantics)" do
    test "creates on first call" do
      sk = "t_seed_#{System.unique_integer([:positive])}"

      {:ok, p} =
        IAM.seed_builtin(%{
          name: "Builtin",
          effect: "deny",
          system_key: sk,
          editable_fields: ["enabled"]
        })

      assert p.system_key == sk
    end

    test "no-ops on second call and preserves user edits" do
      sk = "t_seed_idem_#{System.unique_integer([:positive])}"

      {:ok, p1} =
        IAM.seed_builtin(%{
          name: "Builtin",
          effect: "deny",
          system_key: sk,
          priority: 0,
          editable_fields: ["enabled", "priority"]
        })

      # Simulate operator edit
      {:ok, _} = IAM.update_policy(p1, %{"priority" => 99})

      # Reseed with default priority 0
      {:ok, p2} =
        IAM.seed_builtin(%{
          name: "Builtin",
          effect: "deny",
          system_key: sk,
          priority: 0,
          editable_fields: ["enabled", "priority"]
        })

      # Operator edit preserved
      assert p2.priority == 99
      assert p2.id == p1.id
    end
  end

  describe "bulk_toggle_enabled/2" do
    test "toggles enabled for the given ids" do
      {:ok, a} = IAM.create_policy(%{name: "a", effect: "allow"})
      {:ok, b} = IAM.create_policy(%{name: "b", effect: "allow"})

      {2, _} = IAM.bulk_toggle_enabled([a.id, b.id], false)

      assert {:ok, %Policy{enabled: false}} = IAM.get_policy(a.id)
      assert {:ok, %Policy{enabled: false}} = IAM.get_policy(b.id)
    end
  end
end
