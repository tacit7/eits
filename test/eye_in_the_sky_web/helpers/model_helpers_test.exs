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
      meta_values = ModelHelpers.claude_models_with_meta() |> Enum.map(&elem(&1, 0)) |> MapSet.new()
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
      meta_values = ModelHelpers.codex_models_with_meta() |> Enum.map(&elem(&1, 0)) |> MapSet.new()
      assert meta_values == base_values
    end
  end

  # ---------------------------------------------------------------------------
  # gemini_models/0
  # ---------------------------------------------------------------------------

  describe "gemini_models/0" do
    test "returns a non-empty list" do
      assert ModelHelpers.gemini_models() != []
    end

    test "every entry is a {binary, binary} tuple" do
      for {value, label} <- ModelHelpers.gemini_models() do
        assert is_binary(value)
        assert is_binary(label)
      end
    end

    test "no duplicate values" do
      values = ModelHelpers.gemini_models() |> Enum.map(&elem(&1, 0))
      assert Enum.uniq(values) == values
    end
  end

  # ---------------------------------------------------------------------------
  # gemini_models_with_meta/0
  # ---------------------------------------------------------------------------

  describe "gemini_models_with_meta/0" do
    test "returns a non-empty list" do
      assert ModelHelpers.gemini_models_with_meta() != []
    end

    test "every entry is a 4-element tuple with binary fields" do
      for entry <- ModelHelpers.gemini_models_with_meta() do
        assert tuple_size(entry) == 4

        {value, label, description, color} = entry
        assert is_binary(value)
        assert is_binary(label)
        assert is_binary(description)
        assert is_binary(color)
      end
    end

    test "values match the base gemini_models/0 list" do
      base_values = ModelHelpers.gemini_models() |> Enum.map(&elem(&1, 0)) |> MapSet.new()
      meta_values = ModelHelpers.gemini_models_with_meta() |> Enum.map(&elem(&1, 0)) |> MapSet.new()
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

    test "\"gemini\" returns gemini models" do
      assert ModelHelpers.models_for_provider("gemini") == ModelHelpers.gemini_models()
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

    test "returns a list of binaries for gemini" do
      slugs = ModelHelpers.valid_model_slugs("gemini")
      assert is_list(slugs)
      assert Enum.all?(slugs, &is_binary/1)
    end

    test "no duplicate slugs for any provider" do
      for provider <- ["claude", "codex", "gemini", nil, "unknown"] do
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
      assert ModelHelpers.normalize_model_alias("sonnet") == "claude-sonnet-4-6"
    end

    test "\"opus\" normalizes to opus slug" do
      assert ModelHelpers.normalize_model_alias("opus") == "claude-opus-4-7"
    end

    test "uppercase aliases are case-insensitive" do
      assert ModelHelpers.normalize_model_alias("OPUS") == "claude-opus-4-7"
      assert ModelHelpers.normalize_model_alias("SONNET") == "claude-sonnet-4-6"
      assert ModelHelpers.normalize_model_alias("HAIKU") == "claude-haiku-4-5-20251001"
    end

    test "mixed-case aliases are case-insensitive" do
      assert ModelHelpers.normalize_model_alias("Opus") == "claude-opus-4-7"
      assert ModelHelpers.normalize_model_alias("Sonnet") == "claude-sonnet-4-6"
    end

    test "already-full slug passes through unchanged" do
      assert ModelHelpers.normalize_model_alias("claude-opus-4-7") == "claude-opus-4-7"
      assert ModelHelpers.normalize_model_alias("gpt-5.5") == "gpt-5.5"
      assert ModelHelpers.normalize_model_alias("gemini-2.5-pro") == "gemini-2.5-pro"
    end

    test "nil returns default sonnet slug" do
      assert ModelHelpers.normalize_model_alias(nil) == "claude-sonnet-4-6"
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

    test "\"gemini\" returns gemini-2.5-flash" do
      assert ModelHelpers.default_model_for("gemini") == "gemini-2.5-flash"
    end

    test "\"claude\" returns claude-opus-4-7" do
      assert ModelHelpers.default_model_for("claude") == "claude-opus-4-7"
    end

    test "nil falls back to claude default" do
      assert ModelHelpers.default_model_for(nil) == "claude-opus-4-7"
    end

    test "unknown provider falls back to claude default" do
      assert ModelHelpers.default_model_for("openai") == "claude-opus-4-7"
      assert ModelHelpers.default_model_for("") == "claude-opus-4-7"
    end

    test "default for codex is in valid_model_slugs" do
      assert ModelHelpers.default_model_for("codex") in ModelHelpers.valid_model_slugs("codex")
    end

    test "default for gemini is in valid_model_slugs" do
      assert ModelHelpers.default_model_for("gemini") in ModelHelpers.valid_model_slugs("gemini")
    end
  end

  # ---------------------------------------------------------------------------
  # model_display_name/1
  # ---------------------------------------------------------------------------

  describe "model_display_name/1" do
    test "known claude slug returns its label" do
      assert ModelHelpers.model_display_name("claude-sonnet-4-6") == "Sonnet 4.6"
      assert ModelHelpers.model_display_name("claude-haiku-4-5-20251001") == "Haiku 4.5"
      assert ModelHelpers.model_display_name("claude-opus-4-7") == "Opus 4.7"
    end

    test "known codex slug returns its label" do
      assert ModelHelpers.model_display_name("gpt-5.5") == "GPT-5.5"
      assert ModelHelpers.model_display_name("gpt-5.4-mini") == "GPT-5.4 Mini"
    end

    test "known gemini slug returns its label" do
      assert ModelHelpers.model_display_name("gemini-2.5-pro") == "Gemini 2.5 Pro"
      assert ModelHelpers.model_display_name("gemini-2.5-flash") == "Gemini 2.5 Flash"
    end

    test "short alias \"opus\" returns \"Opus 4.7\"" do
      assert ModelHelpers.model_display_name("opus") == "Opus 4.7"
    end

    test "short alias \"sonnet\" returns \"Sonnet 4.6\"" do
      assert ModelHelpers.model_display_name("sonnet") == "Sonnet 4.6"
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
end
