defmodule EyeInTheSky.Agents.ModelConfig do
  @moduledoc """
  Core configuration for valid provider/model combinations.
  Extracted from the web layer to avoid namespace trespass.
  """

  @doc """
  Returns the list of Claude model slugs.
  """
  def claude_models do
    [
      "claude-opus-4-7",
      "claude-opus-4-6",
      "claude-opus-4-5-20251101",
      "claude-opus-4-1-20250805",
      "claude-sonnet-4-6",
      "claude-sonnet-4-5-20250929",
      "claude-haiku-4-5-20251001",
      # short aliases and [1m] variants kept for backward compat with stored sessions
      "opus",
      "opus[1m]",
      "sonnet",
      "sonnet[1m]",
      "haiku"
    ]
  end

  @doc """
  Returns the list of Codex model slugs.
  """
  def codex_models do
    ["gpt-5.3-codex", "gpt-5.2-codex", "gpt-5.2", "gpt-5.1", "gpt-5-codex-mini"]
  end

  @doc """
  Returns a flat list of valid model slugs for the given provider.
  """
  def valid_model_slugs(provider)
  def valid_model_slugs("codex"), do: codex_models()
  def valid_model_slugs(_), do: claude_models()

  @doc """
  Returns a map of provider => list of valid model slugs.
  """
  def valid_model_combos do
    %{
      "claude" => valid_model_slugs("claude"),
      "codex" => valid_model_slugs("codex")
    }
  end
end
