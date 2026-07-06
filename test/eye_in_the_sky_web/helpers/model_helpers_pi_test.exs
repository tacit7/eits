defmodule EyeInTheSkyWeb.ModelHelpersPiTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Pi.ModelDiscoveryCache, as: Cache
  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  defmodule FakeControl do
    def discover_models,
      do:
        {:ok,
         [
           %{"id" => "ollama-lan/qwen3.6:27b"},
           %{"id" => "google/gemini-2.5-pro"}
         ]}
  end

  setup do
    Application.put_env(:eye_in_the_sky, :pi_control_module, FakeControl)
    Cache.invalidate()

    on_exit(fn ->
      Application.delete_env(:eye_in_the_sky, :pi_control_module)
      Cache.invalidate()
    end)

    :ok
  end

  test "pi_models returns cached slugs with freshness" do
    {:ok, _} = Cache.refresh()

    assert {["ollama-lan/qwen3.6:27b", "google/gemini-2.5-pro"], :fresh} =
             ModelHelpers.pi_models()
  end

  test "pi_models is empty-safe" do
    Cache.invalidate()
    assert {[], :empty} = ModelHelpers.pi_models()
  end

  test "pi_models returns :stale when cache is expired but still populated" do
    {:ok, _} = Cache.refresh()
    Cache.__force_expire_for_test__()
    assert {[_ | _], :stale} = ModelHelpers.pi_models()
  end

  test "models_for_provider(\"pi\") delegates to discovery" do
    {:ok, _} = Cache.refresh()
    assert "ollama-lan/qwen3.6:27b" in ModelHelpers.models_for_provider("pi")
  end

  test "default_model_for(\"pi\") is nil" do
    assert ModelHelpers.default_model_for("pi") == nil
  end
end
