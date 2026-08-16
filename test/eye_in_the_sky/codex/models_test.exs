defmodule EyeInTheSky.Codex.ModelsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Codex.Models

  describe "context_window/1" do
    test "returns 1_050_000 for gpt-5.6-sol" do
      assert Models.context_window("gpt-5.6-sol") == 1_050_000
    end

    test "returns 1_050_000 for gpt-5.6-tenna" do
      assert Models.context_window("gpt-5.6-tenna") == 1_050_000
    end

    test "returns 1_050_000 for gpt-5.6-luna" do
      assert Models.context_window("gpt-5.6-luna") == 1_050_000
    end

    test "returns 1_050_000 for gpt-5.5" do
      assert Models.context_window("gpt-5.5") == 1_050_000
    end

    test "returns 1_050_000 for gpt-5.4" do
      assert Models.context_window("gpt-5.4") == 1_050_000
    end

    test "returns 1_050_000 for gpt-5.4-mini" do
      assert Models.context_window("gpt-5.4-mini") == 1_050_000
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
    test "calculates ~9.5% for gpt-5.4 with 100_000 tokens" do
      assert Models.context_percent("gpt-5.4", 100_000) == 9.5
    end

    test "calculates 100.0% at full context window for gpt-5.4" do
      assert Models.context_percent("gpt-5.4", 1_050_000) == 100.0
    end

    test "calculates 0.0% for zero tokens" do
      assert Models.context_percent("gpt-5.4", 0) == 0.0
    end

    test "calculates correct percent for gpt-5.6-sol" do
      assert Models.context_percent("gpt-5.6-sol", 105_000) == 10.0
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
    test "returns 128_000 for gpt-5.6-sol" do
      assert Models.max_output_tokens("gpt-5.6-sol") == 128_000
    end

    test "returns 128_000 for gpt-5.6-tenna" do
      assert Models.max_output_tokens("gpt-5.6-tenna") == 128_000
    end

    test "returns 128_000 for gpt-5.6-luna" do
      assert Models.max_output_tokens("gpt-5.6-luna") == 128_000
    end

    test "returns 128_000 for gpt-5.5" do
      assert Models.max_output_tokens("gpt-5.5") == 128_000
    end

    test "returns 128_000 for gpt-5.4" do
      assert Models.max_output_tokens("gpt-5.4") == 128_000
    end

    test "returns 128_000 for gpt-5.4-mini" do
      assert Models.max_output_tokens("gpt-5.4-mini") == 128_000
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
