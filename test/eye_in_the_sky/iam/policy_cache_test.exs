defmodule EyeInTheSky.IAM.PolicyCacheTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.IAM
  alias EyeInTheSky.IAM.PolicyCache

  setup do
    PolicyCache.invalidate()
    :ok
  end

  test "miss then hit" do
    {_policies, :miss} = PolicyCache.all_enabled()
    {_policies, :hit} = PolicyCache.all_enabled()
  end

  test "create_policy invalidates cache" do
    {_, _} = PolicyCache.all_enabled()

    {:ok, _p} =
      IAM.create_policy(%{
        name: "t1",
        effect: "allow",
        agent_type: "*",
        action: "*"
      })

    {_, :miss} = PolicyCache.all_enabled()
  end

  test "only enabled policies are cached" do
    {:ok, _} =
      IAM.create_policy(%{
        name: "disabled",
        effect: "allow",
        agent_type: "*",
        action: "*",
        enabled: false
      })

    {:ok, _} =
      IAM.create_policy(%{
        name: "enabled",
        effect: "allow",
        agent_type: "*",
        action: "*",
        enabled: true
      })

    {policies, _} = PolicyCache.all_enabled()
    names = Enum.map(policies, & &1.name)
    assert "enabled" in names
    refute "disabled" in names
  end
end
