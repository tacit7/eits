defmodule EyeInTheSkyWeb.Helpers.ModelHelpers do
  @moduledoc """
  Helpers for Claude, Codex, and Gemini model selection in forms.
  """

  alias EyeInTheSky.Agents.ModelConfig

  defdelegate valid_model_combos, to: ModelConfig

  @doc """
  Returns the list of Claude model {value, label} tuples for select inputs.
  """
  def claude_models do
    [
      {"claude-opus-4-8", "Opus 4.8 (Default)"},
      {"claude-sonnet-4-6", "Sonnet 4.6"},
      {"sonnet[1m]", "Sonnet 4.6 (1M context)"},
      {"claude-haiku-4-5-20251001", "Haiku 4.5"}
    ]
  end

  @doc """
  Returns Claude models with metadata {value, label, description, color} tuples for UI displays.
  """
  def claude_models_with_meta do
    [
      {"claude-opus-4-8", "Opus 4.8", "Best for everyday, complex tasks · 1M context",
       "text-warning"},
      {"claude-sonnet-4-6", "Sonnet 4.6", "Efficient for routine tasks", "text-info"},
      {"sonnet[1m]", "Sonnet 4.6 (1M context)",
       "1M context · Draws from usage credits · $3/$15 per Mtok", "text-info"},
      {"claude-haiku-4-5-20251001", "Haiku 4.5", "Fastest for quick answers", "text-success"}
    ]
  end

  @doc """
  Returns the list of Codex model {value, label} tuples for select inputs.
  """
  def codex_models do
    [
      {"gpt-5.3-codex", "GPT-5.3 Codex (Default)"},
      {"gpt-5.5", "GPT-5.5"},
      {"gpt-5.2", "GPT-5.2"},
      {"gpt-5.4", "GPT-5.4"},
      {"gpt-5.4-mini", "GPT-5.4 Mini"}
    ]
  end

  @doc """
  Returns Codex models with metadata {value, label, description, color} tuples for UI displays.
  """
  def codex_models_with_meta do
    [
      {"gpt-5.3-codex", "GPT-5.3 Codex", "Coding-optimized model (default)", "text-warning"},
      {"gpt-5.5", "GPT-5.5", "Frontier model for complex coding, research, and real-world work",
       "text-warning"},
      {"gpt-5.2", "GPT-5.2", "Optimized for professional work and long-running agents",
       "text-info"},
      {"gpt-5.4", "GPT-5.4", "Strong model for everyday coding", "text-info"},
      {"gpt-5.4-mini", "GPT-5.4 Mini", "Small, fast, and cost-efficient for simpler tasks",
       "text-success"}
    ]
  end

  @doc """
  Returns the list of Gemini model {value, label} tuples for select inputs.
  """
  def gemini_models do
    [
      {"gemini-2.5-pro", "Gemini 2.5 Pro"},
      {"gemini-2.5-flash", "Gemini 2.5 Flash"},
      {"gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite"}
    ]
  end

  @doc """
  Returns Gemini models with metadata {value, label, description, color} tuples for UI displays.
  """
  def gemini_models_with_meta do
    [
      {"gemini-2.5-pro", "Gemini 2.5 Pro", "Most capable Gemini · long context", "text-warning"},
      {"gemini-2.5-flash", "Gemini 2.5 Flash", "Balanced speed and quality (default)",
       "text-info"},
      {"gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite", "Cheapest and fastest", "text-success"}
    ]
  end

  @doc """
  Returns {value, label} tuples for the given provider.
  """
  def models_for_provider("codex"), do: codex_models()
  def models_for_provider("gemini"), do: gemini_models()
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
      "opus" -> "claude-opus-4-8"
      _ -> model
    end
  end

  def normalize_model_alias(nil), do: "claude-sonnet-4-6"

  @doc """
  Returns the default model slug for a provider.
  """
  def default_model_for("codex"), do: "gpt-5.3-codex"
  def default_model_for("gemini"), do: "gemini-2.5-flash"
  def default_model_for(_), do: "claude-opus-4-8"

  @doc """
  Returns a human-readable display name for any supported model slug,
  including backward-compat short aliases. Falls back to the slug itself.
  """
  def model_display_name(slug) when is_binary(slug) do
    case Enum.find(claude_models() ++ codex_models() ++ gemini_models(), fn {val, _} ->
           val == slug
         end) do
      {_, label} -> label
      nil -> short_alias_display(slug)
    end
  end

  def model_display_name(other), do: to_string(other)

  defp short_alias_display("opus"), do: "Opus 4.8"
  defp short_alias_display("opus[1m]"), do: "Opus 4.7 (1M)"
  defp short_alias_display("sonnet"), do: "Sonnet 4.6"
  defp short_alias_display("sonnet[1m]"), do: "Sonnet 4.6 (1M)"
  defp short_alias_display("haiku"), do: "Haiku 4.5"
  defp short_alias_display("claude-opus-4-8"), do: "Opus 4.8"
  defp short_alias_display("claude-opus-4-7"), do: "Opus 4.7"
  defp short_alias_display("claude-opus-4-6"), do: "Opus 4.6"
  defp short_alias_display(other), do: other
end
