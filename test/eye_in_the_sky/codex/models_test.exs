defmodule EyeInTheSky.Codex.ModelsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Codex.Models

  describe "context_window/1" do
    test "returns 1_050_000 for gpt-5.5" do
      assert Models.context_window("gpt-5.5") == 1_050_000
    end

    test "returns 1_000_000 for gpt-5.4" do
      assert Models.context_window("gpt-5.4") == 1_000_000
    end

    test "returns nil for gpt-5.6-sol (size not yet confirmed)" do
      assert Models.context_window("gpt-5.6-sol") == nil
    end

    test "returns nil for gpt-5.6-terra (size not yet confirmed)" do
      assert Models.context_window("gpt-5.6-terra") == nil
    end

    test "returns nil for gpt-5.6-luna (size not yet confirmed)" do
      assert Models.context_window("gpt-5.6-luna") == nil
    end

    test "returns nil for gpt-5.4-mini (size not yet confirmed)" do
      assert Models.context_window("gpt-5.4-mini") == nil
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

    test "calculates 100.0% at full context window for gpt-5.4" do
      assert Models.context_percent("gpt-5.4", 1_000_000) == 100.0
    end

    test "calculates 0.0% for zero tokens" do
      assert Models.context_percent("gpt-5.4", 0) == 0.0
    end

    test "returns nil for gpt-5.6-sol (window unknown)" do
      assert Models.context_percent("gpt-5.6-sol", 100_000) == nil
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
  end

  describe "max_output_tokens/1" do
    test "returns 128_000 for gpt-5.5" do
      assert Models.max_output_tokens("gpt-5.5") == 128_000
    end

    test "returns nil for gpt-5.4 (not in max output map)" do
      assert Models.max_output_tokens("gpt-5.4") == nil
    end

    test "returns nil for gpt-5.6-sol (not yet confirmed)" do
      assert Models.max_output_tokens("gpt-5.6-sol") == nil
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
