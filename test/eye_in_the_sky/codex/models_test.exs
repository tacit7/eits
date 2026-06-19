defmodule EyeInTheSky.Codex.ModelsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Codex.Models

  describe "context_window/1" do
    test "returns 1_000_000 for gpt-5.4" do
      assert Models.context_window("gpt-5.4") == 1_000_000
    end

    test "returns 400_000 for gpt-5.3-codex" do
      assert Models.context_window("gpt-5.3-codex") == 400_000
    end

    test "returns 400_000 for gpt-5.2" do
      assert Models.context_window("gpt-5.2") == 400_000
    end

    test "returns 400_000 for gpt-5.1-codex-max" do
      assert Models.context_window("gpt-5.1-codex-max") == 400_000
    end

    test "returns 400_000 for gpt-5.2-codex" do
      assert Models.context_window("gpt-5.2-codex") == 400_000
    end

    test "returns 400_000 for gpt-5.1-codex-mini" do
      assert Models.context_window("gpt-5.1-codex-mini") == 400_000
    end

    test "returns nil for unknown model" do
      assert Models.context_window("gpt-4o") == nil
    end

    test "returns nil for nil input" do
      assert Models.context_window(nil) == nil
    end

    test "returns nil for empty string" do
      assert Models.context_window("") == nil
    end
  end

  describe "context_percent/2" do
    test "calculates 25.0% for gpt-5.4 with 250_000 tokens" do
      assert Models.context_percent("gpt-5.4", 250_000) == 25.0
    end

    test "calculates 12.5% for gpt-5.3-codex with 50_000 tokens" do
      assert Models.context_percent("gpt-5.3-codex", 50_000) == 12.5
    end

    test "calculates 100.0% at full context window" do
      assert Models.context_percent("gpt-5.4", 1_000_000) == 100.0
    end

    test "calculates 0.0% for zero tokens" do
      assert Models.context_percent("gpt-5.4", 0) == 0.0
    end

    test "rounds to one decimal place" do
      # 1 / 400_000 * 100 = 0.00025 -> rounds to 0.0
      assert Models.context_percent("gpt-5.2", 1) == 0.0
    end

    test "returns nil for unknown model" do
      assert Models.context_percent("gpt-4o", 1000) == nil
    end

    test "returns nil when model is nil" do
      assert Models.context_percent(nil, 1000) == nil
    end

    test "returns nil when model is empty string" do
      assert Models.context_percent("", 1000) == nil
    end

    test "calculates correct percent for gpt-5.1-codex-mini" do
      assert Models.context_percent("gpt-5.1-codex-mini", 40_000) == 10.0
    end
  end

  describe "max_output_tokens/1" do
    test "returns 128_000 for gpt-5.3-codex" do
      assert Models.max_output_tokens("gpt-5.3-codex") == 128_000
    end

    test "returns 128_000 for gpt-5.2" do
      assert Models.max_output_tokens("gpt-5.2") == 128_000
    end

    test "returns 128_000 for gpt-5.1-codex-max" do
      assert Models.max_output_tokens("gpt-5.1-codex-max") == 128_000
    end

    test "returns 128_000 for gpt-5.2-codex" do
      assert Models.max_output_tokens("gpt-5.2-codex") == 128_000
    end

    test "returns 128_000 for gpt-5.1-codex-mini" do
      assert Models.max_output_tokens("gpt-5.1-codex-mini") == 128_000
    end

    test "returns nil for gpt-5.4 (not in max output map)" do
      assert Models.max_output_tokens("gpt-5.4") == nil
    end

    test "returns nil for unknown model" do
      assert Models.max_output_tokens("gpt-4o") == nil
    end

    test "returns nil for nil input" do
      assert Models.max_output_tokens(nil) == nil
    end

    test "returns nil for empty string" do
      assert Models.max_output_tokens("") == nil
    end
  end
end
