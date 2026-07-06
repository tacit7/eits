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

  test "models_for_provider(\"pi\") returns {slug, slug} tuples matching the destructuring contract" do
    {:ok, _} = Cache.refresh()

    result = ModelHelpers.models_for_provider("pi")

    # Every entry must be a {value, label} tuple — new_session_modal.ex:436
    # pattern-matches `for {value, label} <- models_for_provider(...)` and
    # would crash on bare strings.
    for entry <- result do
      assert match?({slug, slug} when is_binary(slug), entry),
             "expected {slug, slug} tuple, got: #{inspect(entry)}"
    end

    assert {"ollama-lan/qwen3.6:27b", "ollama-lan/qwen3.6:27b"} in result
  end

  test "models_for_provider(\"pi\") is empty-safe (never crashes when cache is cold)" do
    Cache.invalidate()
    assert [] = ModelHelpers.models_for_provider("pi")
  end

  test "valid_model_slugs(\"pi\") returns flat slugs, not tuples" do
    {:ok, _} = Cache.refresh()
    slugs = ModelHelpers.valid_model_slugs("pi")
    assert "ollama-lan/qwen3.6:27b" in slugs
    assert "google/gemini-2.5-pro" in slugs
  end

  test "default_model_for(\"pi\") is nil" do
    assert ModelHelpers.default_model_for("pi") == nil
  end
end
