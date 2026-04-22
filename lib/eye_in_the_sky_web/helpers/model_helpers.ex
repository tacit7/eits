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
      {"claude-opus-4-5-20251101", "Opus 4.5"},
      {"claude-opus-4-1-20250805", "Opus 4.1"},
      {"claude-sonnet-4-6", "Sonnet 4.6"},
      {"claude-sonnet-4-5-20250929", "Sonnet 4.5"},
      {"claude-haiku-4-5-20251001", "Haiku 4.5"}
    ]
  end

  @doc """
  Returns Claude models with metadata {value, label, description, color} tuples for UI displays.
  """
  def claude_models_with_meta do
    [
      {"claude-opus-4-7", "Opus 4.7", "Most capable for complex work · 1M context", "text-warning"},
      {"claude-opus-4-5-20251101", "Opus 4.5", "api", "text-warning"},
      {"claude-opus-4-1-20250805", "Opus 4.1", "api", "text-warning"},
      {"claude-sonnet-4-6", "Sonnet 4.6", "Best for everyday tasks", "text-info"},
      {"claude-sonnet-4-5-20250929", "Sonnet 4.5", "api", "text-info"},
      {"claude-haiku-4-5-20251001", "Haiku 4.5", "Fastest for quick answers", "text-success"}
    ]
  end

  @doc """
  Returns the list of Codex model {value, label} tuples for select inputs.
  """
  def codex_models do
    [
      {"gpt-5.4", "GPT-5.4"},
      {"gpt-5.2-codex", "GPT-5.2 Codex"},
      {"gpt-5.1-codex-max", "GPT-5.1 Codex Max"},
      {"gpt-5.4-mini", "GPT-5.4 Mini"},
      {"gpt-5.3-codex", "GPT-5.3 Codex"},
      {"gpt-5.2", "GPT-5.2"},
      {"gpt-5.1-codex-mini", "GPT-5.1 Codex Mini"}
    ]
  end

  @doc """
  Returns Codex models with metadata {value, label, description, color} tuples for UI displays.
  """
  def codex_models_with_meta do
    [
      {"gpt-5.4", "GPT-5.4", "Latest frontier agentic coding (default)", "text-warning"},
      {"gpt-5.2-codex", "GPT-5.2 Codex", "Frontier Codex-optimized", "text-warning"},
      {"gpt-5.1-codex-max", "GPT-5.1 Codex Max", "Deep reasoning, large context", "text-warning"},
      {"gpt-5.4-mini", "GPT-5.4 Mini", "Cheaper 5.4 tier", "text-info"},
      {"gpt-5.3-codex", "GPT-5.3 Codex", "Frontier agentic coding", "text-info"},
      {"gpt-5.2", "GPT-5.2", "Long-running agents", "text-info"},
      {"gpt-5.1-codex-mini", "GPT-5.1 Codex Mini", "Cheaper and faster", "text-success"}
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

  @doc """
  Normalizes a model alias to its full API name.
  Settings stores short aliases (opus, sonnet, haiku) but form options use full names.
  """
  def normalize_model_alias(model) when is_binary(model) do
    case String.downcase(model) do
      "haiku" -> "claude-haiku-4-5-20251001"
      "sonnet" -> "claude-sonnet-4-6"
      "opus" -> "claude-opus-4-7"
      _ -> model
    end
  end

  def normalize_model_alias(nil), do: "claude-sonnet-4-6"

  @doc """
  Returns the default model slug for a provider.
  """
  def default_model_for("codex"), do: "gpt-5.4"
  def default_model_for(_), do: "claude-opus-4-7"

  @doc """
  Returns a human-readable display name for any supported model slug,
  including backward-compat short aliases. Falls back to the slug itself.
  """
  def model_display_name(slug) when is_binary(slug) do
    case Enum.find(claude_models() ++ codex_models(), fn {val, _} -> val == slug end) do
      {_, label} -> label
      nil -> short_alias_display(slug)
    end
  end

  def model_display_name(other), do: to_string(other)

  defp short_alias_display("opus"), do: "Opus 4.7"
  defp short_alias_display("opus[1m]"), do: "Opus 4.6 (1M)"
  defp short_alias_display("sonnet"), do: "Sonnet 4.6"
  defp short_alias_display("sonnet[1m]"), do: "Sonnet 4.5 (1M)"
  defp short_alias_display("haiku"), do: "Haiku 4.5"
  defp short_alias_display("claude-opus-4-6"), do: "Opus 4.6"
  defp short_alias_display(other), do: other
end
