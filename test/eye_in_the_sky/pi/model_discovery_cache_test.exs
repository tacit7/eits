defmodule EyeInTheSky.Pi.ModelDiscoveryCacheTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Pi.ModelDiscoveryCache, as: Cache

  defmodule FakeControl do
    def discover_models do
      Application.get_env(:eye_in_the_sky, :fake_discover, {:ok, [%{"id" => "ollama/mistral"}]})
    end
  end

  setup do
    Application.put_env(:eye_in_the_sky, :pi_control_module, FakeControl)
    Cache.invalidate()

    on_exit(fn ->
      Application.delete_env(:eye_in_the_sky, :pi_control_module)
      Application.delete_env(:eye_in_the_sky, :fake_discover)
      Cache.invalidate()
    end)

    :ok
  end

  test "get_cached is :empty before any refresh" do
    assert :empty = Cache.get_cached()
  end

  test "refresh stores models; get_cached returns :fresh" do
    Application.put_env(:eye_in_the_sky, :fake_discover, {:ok, [%{"id" => "a/b"}]})
    assert {:ok, [%{"id" => "a/b"}]} = Cache.refresh()
    assert {:ok, [%{"id" => "a/b"}], :fresh} = Cache.get_cached()
  end

  test "entries older than TTL read as :stale but are still returned" do
    Application.put_env(:eye_in_the_sky, :fake_discover, {:ok, [%{"id" => "a/b"}]})
    {:ok, _} = Cache.refresh()
    Cache.__force_expire_for_test__()
    assert {:ok, [%{"id" => "a/b"}], :stale} = Cache.get_cached()
  end

  test "refresh failure keeps the previous cached list" do
    Application.put_env(:eye_in_the_sky, :fake_discover, {:ok, [%{"id" => "a/b"}]})
    {:ok, _} = Cache.refresh()
    Application.put_env(:eye_in_the_sky, :fake_discover, {:error, :pi_control_timeout})
    assert {:error, :pi_control_timeout} = Cache.refresh()
    assert {:ok, [%{"id" => "a/b"}], _} = Cache.get_cached()
  end

  test "invalidate clears" do
    Application.put_env(:eye_in_the_sky, :fake_discover, {:ok, [%{"id" => "a/b"}]})
    {:ok, _} = Cache.refresh()
    Cache.invalidate()
    assert :empty = Cache.get_cached()
  end

  test "refresh_async broadcasts result to subscribers" do
    Application.put_env(:eye_in_the_sky, :fake_discover, {:ok, [%{"id" => "x/y"}]})
    :ok = EyeInTheSky.Events.subscribe_pi_models()
    :ok = Cache.refresh_async()
    assert_receive {:pi_models_refreshed, {:ok, [%{"id" => "x/y"}]}}, 2_000
  end
end
