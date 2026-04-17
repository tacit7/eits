defmodule EyeInTheSkyWeb.Helpers.ModelHelpers do
  @moduledoc """
  Helpers for Claude and Codex model selection in forms.
  """

  alias EyeInTheSky.Agents.ModelConfig

  defdelegate valid_model_combos, to: ModelConfig

  @doc """
  Returns the list of Claude model {value, label} tuples for select inputs.
  """
  def claude_models do
    [
      {"claude-opus-4-7", "Opus 4.7"},
      {"claude-opus-4-6", "Opus 4.6"},
      {"claude-opus-4-5-20251101", "Opus 4.5"},
      {"claude-opus-4-1-20250805", "Opus 4.1"},
      {"claude-sonnet-4-6", "Sonnet 4.6"},
      {"claude-sonnet-4-5-20250929", "Sonnet 4.5"},
      {"claude-haiku-4-5-20251001", "Haiku 4.5"}
    ]
  end

  @doc """
  Returns the list of Codex model {value, label} tuples for select inputs.
  """
  def codex_models do
    [
      {"gpt-5.3-codex", "GPT-5.3 Codex"},
      {"gpt-5.2-codex", "GPT-5.2 Codex"},
      {"gpt-5.2", "GPT-5.2"},
      {"gpt-5.1", "GPT-5.1"},
      {"gpt-5-codex-mini", "GPT-5 Codex Mini"}
    ]
  end

  @doc """
  Returns {value, label} tuples for the given provider.
  """
  def models_for_provider("codex"), do: codex_models()
  def models_for_provider(_), do: claude_models()

  @doc """
  Returns a flat list of valid model slugs for the given provider.
  """
  def valid_model_slugs(provider) do
    provider |> models_for_provider() |> Enum.map(&elem(&1, 0))
  end
end
