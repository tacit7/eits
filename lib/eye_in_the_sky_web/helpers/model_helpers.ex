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
      {"sonnet", "Sonnet 4.5"},
      {"opus", "Opus 4.6"},
      {"sonnet[1m]", "Sonnet 4.5 (1M)"},
      {"opus[1m]", "Opus 4.6 (1M)"},
      {"haiku", "Haiku 4.5"}
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
