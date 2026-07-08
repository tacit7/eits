defmodule EyeInTheSkyWeb.Helpers.ModelHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  # ---------------------------------------------------------------------------
  # claude_models/0
  # ---------------------------------------------------------------------------

  describe "claude_models/0" do
    test "returns a non-empty list" do
      assert ModelHelpers.claude_models() != []
    end

    test "every entry is a {binary, binary} tuple" do
      for {value, label} <- ModelHelpers.claude_models() do
        assert is_binary(value), "expected binary value, got #{inspect(value)}"
        assert is_binary(label), "expected binary label, got #{inspect(label)}"
      end
    end

    test "includes the expected default sonnet slug" do
      values = ModelHelpers.claude_models() |> Enum.map(&elem(&1, 0))
      assert "claude-sonnet-4-6" in values
    end

    test "no duplicate values" do
      values = ModelHelpers.claude_models() |> Enum.map(&elem(&1, 0))
      assert Enum.uniq(values) == values
    end
  end

  # ---------------------------------------------------------------------------
  # claude_models_with_meta/0
  # ---------------------------------------------------------------------------

  describe "claude_models_with_meta/0" do
    test "returns a non-empty list" do
      assert ModelHelpers.claude_models_with_meta() != []
    end

    test "every entry is a 4-element tuple with binary fields" do
      for entry <- ModelHelpers.claude_models_with_meta() do
        assert tuple_size(entry) == 4,
               "expected 4-tuple, got #{inspect(entry)}"

        {value, label, description, color} = entry
        assert is_binary(value)
        assert is_binary(label)
        assert is_binary(description)
        assert is_binary(color)
      end
    end

    test "values match the base claude_models/0 list" do
      base_values = ModelHelpers.claude_models() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      meta_values =
        ModelHelpers.claude_models_with_meta() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      assert meta_values == base_values
    end
  end

  # ---------------------------------------------------------------------------
  # codex_models/0
  # ---------------------------------------------------------------------------

  describe "codex_models/0" do
    test "returns a non-empty list" do
      assert ModelHelpers.codex_models() != []
    end

    test "every entry is a {binary, binary} tuple" do
      for {value, label} <- ModelHelpers.codex_models() do
        assert is_binary(value)
        assert is_binary(label)
      end
    end

    test "no duplicate values" do
      values = ModelHelpers.codex_models() |> Enum.map(&elem(&1, 0))
      assert Enum.uniq(values) == values
    end
  end

  # ---------------------------------------------------------------------------
  # codex_models_with_meta/0
  # ---------------------------------------------------------------------------

  describe "codex_models_with_meta/0" do
    test "returns a non-empty list" do
      assert ModelHelpers.codex_models_with_meta() != []
    end

    test "every entry is a 4-element tuple with binary fields" do
      for entry <- ModelHelpers.codex_models_with_meta() do
        assert tuple_size(entry) == 4

        {value, label, description, color} = entry
        assert is_binary(value)
        assert is_binary(label)
        assert is_binary(description)
        assert is_binary(color)
      end
    end

    test "values match the base codex_models/0 list" do
      base_values = ModelHelpers.codex_models() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      meta_values =
        ModelHelpers.codex_models_with_meta() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      assert meta_values == base_values
    end
  end

  # ---------------------------------------------------------------------------
  # models_for_provider/1
  # ---------------------------------------------------------------------------

  describe "models_for_provider/1" do
    test "\"codex\" returns codex models" do
      assert ModelHelpers.models_for_provider("codex") == ModelHelpers.codex_models()
    end

    test "\"claude\" returns claude models" do
      assert ModelHelpers.models_for_provider("claude") == ModelHelpers.claude_models()
    end

    test "nil falls back to claude models" do
      assert ModelHelpers.models_for_provider(nil) == ModelHelpers.claude_models()
    end

    test "unknown provider falls back to claude models" do
      assert ModelHelpers.models_for_provider("openai") == ModelHelpers.claude_models()
      assert ModelHelpers.models_for_provider("") == ModelHelpers.claude_models()
    end
  end

  # ---------------------------------------------------------------------------
  # valid_model_slugs/1
  # ---------------------------------------------------------------------------

  describe "valid_model_slugs/1" do
    test "returns a list of binaries for claude" do
      slugs = ModelHelpers.valid_model_slugs("claude")
      assert is_list(slugs)
      assert Enum.all?(slugs, &is_binary/1)
    end

    test "returns a list of binaries for codex" do
      slugs = ModelHelpers.valid_model_slugs("codex")
      assert is_list(slugs)
      assert Enum.all?(slugs, &is_binary/1)
    end

    test "no duplicate slugs for any provider" do
      for provider <- ["claude", "codex", nil, "unknown"] do
        slugs = ModelHelpers.valid_model_slugs(provider)
        assert Enum.uniq(slugs) == slugs, "duplicates for provider #{inspect(provider)}"
      end
    end

    test "slug list matches the first element of each model tuple" do
      assert ModelHelpers.valid_model_slugs("codex") ==
               ModelHelpers.codex_models() |> Enum.map(&elem(&1, 0))
    end
  end

  # ---------------------------------------------------------------------------
  # normalize_model_alias/1
  # ---------------------------------------------------------------------------

  describe "normalize_model_alias/1" do
    test "\"haiku\" normalizes to haiku slug" do
      assert ModelHelpers.normalize_model_alias("haiku") == "claude-haiku-4-5-20251001"
    end

    test "\"sonnet\" normalizes to sonnet slug" do
      assert ModelHelpers.normalize_model_alias("sonnet") == "claude-sonnet-5"
    end

    test "\"opus\" normalizes to opus slug" do
      assert ModelHelpers.normalize_model_alias("opus") == "claude-opus-4-8"
    end

    test "uppercase aliases are case-insensitive" do
      assert ModelHelpers.normalize_model_alias("OPUS") == "claude-opus-4-8"
      assert ModelHelpers.normalize_model_alias("SONNET") == "claude-sonnet-5"
      assert ModelHelpers.normalize_model_alias("HAIKU") == "claude-haiku-4-5-20251001"
    end

    test "mixed-case aliases are case-insensitive" do
      assert ModelHelpers.normalize_model_alias("Opus") == "claude-opus-4-8"
      assert ModelHelpers.normalize_model_alias("Sonnet") == "claude-sonnet-5"
    end

    test "already-full slug passes through unchanged" do
      assert ModelHelpers.normalize_model_alias("claude-opus-4-7") == "claude-opus-4-7"
      assert ModelHelpers.normalize_model_alias("gpt-5.5") == "gpt-5.5"
      assert ModelHelpers.normalize_model_alias("gpt-5.1-codex-mini") == "gpt-5.1-codex-mini"
    end

    test "nil returns default sonnet slug" do
      assert ModelHelpers.normalize_model_alias(nil) == "claude-sonnet-5"
    end

    test "unknown string passes through unchanged" do
      assert ModelHelpers.normalize_model_alias("unknown-model") == "unknown-model"
    end
  end

  # ---------------------------------------------------------------------------
  # default_model_for/1
  # ---------------------------------------------------------------------------

  describe "default_model_for/1" do
    test "\"codex\" returns gpt-5.5" do
      assert ModelHelpers.default_model_for("codex") == "gpt-5.5"
    end

    test "\"claude\" returns claude-opus-4-8" do
      assert ModelHelpers.default_model_for("claude") == "claude-opus-4-8"
    end

    test "nil falls back to claude default" do
      assert ModelHelpers.default_model_for(nil) == "claude-opus-4-8"
    end

    test "unknown provider falls back to claude default" do
      assert ModelHelpers.default_model_for("openai") == "claude-opus-4-8"
      assert ModelHelpers.default_model_for("") == "claude-opus-4-8"
    end

    test "default for codex is in valid_model_slugs" do
      assert ModelHelpers.default_model_for("codex") in ModelHelpers.valid_model_slugs("codex")
    end

  end

  # ---------------------------------------------------------------------------
  # model_display_name/1
  # ---------------------------------------------------------------------------

  describe "model_display_name/1" do
    test "known claude slug returns its label" do
      assert ModelHelpers.model_display_name("claude-sonnet-4-6") == "Sonnet 4.6"
      assert ModelHelpers.model_display_name("claude-haiku-4-5-20251001") == "Haiku 4.5"
      assert ModelHelpers.model_display_name("claude-opus-4-8") == "Opus 4.8"
    end

    test "known codex slug returns its label" do
      assert ModelHelpers.model_display_name("gpt-5.5") == "GPT-5.5"
      assert ModelHelpers.model_display_name("gpt-5.4-mini") == "GPT-5.4 Mini"
    end

    test "short alias \"opus\" returns \"Opus 4.8\"" do
      assert ModelHelpers.model_display_name("opus") == "Opus 4.8"
    end

    test "short alias \"sonnet\" returns \"Sonnet 5\"" do
      assert ModelHelpers.model_display_name("sonnet") == "Sonnet 5"
    end

    test "short alias \"haiku\" returns \"Haiku 4.5\"" do
      assert ModelHelpers.model_display_name("haiku") == "Haiku 4.5"
    end

    test "unknown slug returns the slug itself" do
      assert ModelHelpers.model_display_name("some-unknown-model") == "some-unknown-model"
    end

    test "nil returns empty string" do
      assert ModelHelpers.model_display_name(nil) == ""
    end

    test "integer input is converted to string" do
      assert ModelHelpers.model_display_name(42) == "42"
    end
  end

  # ---------------------------------------------------------------------------
  # entries_for_provider/1
  # ---------------------------------------------------------------------------

  defmodule FakeControl do
    def discover_models do
      {:ok,
       [
         %{"id" => "ollama-lan/qwen3.6:27b", "provider" => "ollama-lan"},
         %{"id" => "openrouter/qwen/qwen3-coder", "provider" => "openrouter"}
       ]}
    end
  end

  describe "entries_for_provider/1 — claude" do
    setup do
      %{entries: ModelHelpers.entries_for_provider("claude")}
    end

    test "every entry has provider \"claude\" and group \"Claude Code\"", %{entries: entries} do
      assert entries != []
      assert Enum.all?(entries, &(&1.provider == "claude"))
      assert Enum.all?(entries, &(&1.group == "Claude Code"))
    end

    test "primary current-gen models are not legacy", %{entries: entries} do
      by_slug = Map.new(entries, &{&1.slug, &1})
      assert by_slug["claude-opus-4-8"].legacy? == false
      assert by_slug["claude-fable-5"].legacy? == false
      assert by_slug["claude-sonnet-5"].legacy? == false
      assert by_slug["claude-haiku-4-5-20251001"].legacy? == false
    end

    test "older generation models are legacy", %{entries: entries} do
      by_slug = Map.new(entries, &{&1.slug, &1})
      assert by_slug["claude-opus-4-7"].legacy? == true
      assert by_slug["claude-sonnet-4-6"].legacy? == true
    end

    test "opus[1m] and sonnet[1m] are premium", %{entries: entries} do
      by_slug = Map.new(entries, &{&1.slug, &1})
      assert by_slug["opus[1m]"].premium? == true
      assert by_slug["sonnet[1m]"].premium? == true
    end

    test "non-1m entries are not premium", %{entries: entries} do
      refute Enum.any?(entries, &(&1.slug == "claude-opus-4-8" and &1.premium?))
    end

    test "exactly one default entry, on claude-opus-4-8", %{entries: entries} do
      defaults = Enum.filter(entries, & &1.default?)
      assert [%{slug: "claude-opus-4-8"}] = defaults
    end
  end

  describe "entries_for_provider/1 — codex" do
    setup do
      %{entries: ModelHelpers.entries_for_provider("codex")}
    end

    test "every entry has provider \"codex\" and group \"Codex\", never premium", %{entries: entries} do
      assert entries != []
      assert Enum.all?(entries, &(&1.provider == "codex"))
      assert Enum.all?(entries, &(&1.group == "Codex"))
      refute Enum.any?(entries, & &1.premium?)
    end

    test "gpt-5.5, gpt-5.4, gpt-5.4-mini are primary; rest are legacy", %{entries: entries} do
      by_slug = Map.new(entries, &{&1.slug, &1})
      assert by_slug["gpt-5.5"].legacy? == false
      assert by_slug["gpt-5.4"].legacy? == false
      assert by_slug["gpt-5.4-mini"].legacy? == false
      assert by_slug["gpt-5.3-codex"].legacy? == true
      assert by_slug["gpt-5.1-codex-max"].legacy? == true
    end

    test "default is gpt-5.5", %{entries: entries} do
      assert [%{slug: "gpt-5.5"}] = Enum.filter(entries, & &1.default?)
    end
  end

  describe "entries_for_provider/1 — pi" do
    test "preserves sub_provider from discovery and marks non-ollama as premium" do
      Application.put_env(:eye_in_the_sky, :pi_control_module, __MODULE__.FakeControl)
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :pi_control_module) end)
      {:ok, _} = EyeInTheSky.Pi.ModelDiscoveryCache.refresh()

      entries = ModelHelpers.entries_for_provider("pi")
      by_slug = Map.new(entries, &{&1.slug, &1})

      assert by_slug["ollama-lan/qwen3.6:27b"].provider == "pi"
      assert by_slug["ollama-lan/qwen3.6:27b"].sub_provider == "ollama-lan"
      assert by_slug["ollama-lan/qwen3.6:27b"].premium? == false

      assert by_slug["openrouter/qwen/qwen3-coder"].sub_provider == "openrouter"
      assert by_slug["openrouter/qwen/qwen3-coder"].premium? == true
    end

    test "empty cache returns empty list, does not crash" do
      EyeInTheSky.Pi.ModelDiscoveryCache.invalidate()
      assert ModelHelpers.entries_for_provider("pi") == []
    end
  end

  describe "all_model_entries/0" do
    test "concatenates claude, codex, and pi entries" do
      entries = ModelHelpers.all_model_entries()
      providers = entries |> Enum.map(& &1.provider) |> Enum.uniq() |> Enum.sort()
      assert "claude" in providers
      assert "codex" in providers
    end
  end

  # ---------------------------------------------------------------------------
  # catalog refresh (Task 1)
  # ---------------------------------------------------------------------------

  describe "claude_models/0 — refreshed catalog" do
    test "includes the refreshed Claude 5 family slugs" do
      values = ModelHelpers.claude_models() |> Enum.map(&elem(&1, 0))
      assert "claude-opus-4-8" in values
      assert "claude-fable-5" in values
      assert "claude-sonnet-5" in values
      assert "claude-haiku-4-5-20251001" in values
    end

    test "keeps old-generation slugs for existing sessions (spec §6.3 migration note)" do
      values = ModelHelpers.claude_models() |> Enum.map(&elem(&1, 0))
      assert "claude-opus-4-7" in values
      assert "claude-sonnet-4-6" in values
    end
  end
end
