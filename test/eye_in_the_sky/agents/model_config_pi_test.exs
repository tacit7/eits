defmodule EyeInTheSky.Agents.ModelConfigPiTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Agents.{ModelConfig, SpawnValidator}

  test "pi model format validation" do
    assert ModelConfig.valid_model?("pi", "google/gemini-2.5-pro")
    assert ModelConfig.valid_model?("pi", "openrouter/qwen/qwen3-coder")
    assert ModelConfig.valid_model?("pi", "openrouter/anthropic/claude-3.5-sonnet@beta")
    refute ModelConfig.valid_model?("pi", "no-slash")
    refute ModelConfig.valid_model?("pi", "has space/model")
    refute ModelConfig.valid_model?("pi", nil)
  end

  test "non-pi providers keep list-based validation" do
    assert ModelConfig.valid_model?("codex", "gpt-5.5")
    refute ModelConfig.valid_model?("codex", "made-up")
  end

  test "default_model for pi is nil (resolved from discovery in Phase 2)" do
    assert ModelConfig.default_model("pi") == nil
  end

  test "pi_split_model! splits on the FIRST slash only" do
    assert ModelConfig.pi_split_model!("openrouter/qwen/qwen3-coder") == {"openrouter", "qwen/qwen3-coder"}
  end

  test "spawn validator accepts pi with explicit model" do
    assert {:ok, params} =
             SpawnValidator.validate(%{
               "instructions" => "do the thing",
               "provider" => "pi",
               "model" => "google/gemini-2.5-pro"
             })

    assert params["provider"] == "pi"
  end

  test "spawn validator rejects pi without a model, pointing at settings" do
    assert {:error, "invalid_model", message} =
             SpawnValidator.validate(%{"instructions" => "x", "provider" => "pi"})

    assert message =~ "pi"
  end
end
