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
      {"claude-opus-4-8", "Opus 4.8"},
      {"claude-fable-5", "Fable 5"},
      {"claude-sonnet-5", "Sonnet 5"},
      {"claude-haiku-4-5-20251001", "Haiku 4.5"},
      {"claude-opus-4-7", "Opus 4.7"},
      {"claude-opus-4-6", "Opus 4.6"},
      {"claude-opus-4-5-20251101", "Opus 4.5"},
      {"claude-opus-4-1-20250805", "Opus 4.1"},
      {"claude-sonnet-4-6", "Sonnet 4.6"},
      {"claude-sonnet-4-5-20250929", "Sonnet 4.5"}
    ]
  end

  @doc """
  Returns Claude models with metadata {value, label, description, color} tuples for UI displays.
  """
  def claude_models_with_meta do
    [
      {"claude-opus-4-8", "Opus 4.8", "Best for everyday, complex tasks · 1M context",
       "text-warning"},
      {"claude-fable-5", "Fable 5", "Most capable for your hardest and longest-running tasks",
       "text-warning"},
      {"claude-sonnet-5", "Sonnet 5", "Efficient for routine tasks", "text-info"},
      {"claude-haiku-4-5-20251001", "Haiku 4.5", "Fastest for quick answers", "text-success"},
      {"claude-opus-4-7", "Opus 4.7", "Previous generation · 1M context", "text-warning"},
      {"claude-opus-4-6", "Opus 4.6", "Previous generation · 1M context · extended thinking",
       "text-warning"},
      {"claude-opus-4-5-20251101", "Opus 4.5", "api", "text-warning"},
      {"claude-opus-4-1-20250805", "Opus 4.1", "api", "text-warning"},
      {"claude-sonnet-4-6", "Sonnet 4.6", "Previous generation", "text-info"},
      {"claude-sonnet-4-5-20250929", "Sonnet 4.5", "api", "text-info"}
    ]
  end

  @doc """
  Returns the list of Codex model {value, label} tuples for select inputs.
  """
  def codex_models do
    [
      {"gpt-5.5", "GPT-5.5"},
      {"gpt-5.4", "GPT-5.4"},
      {"gpt-5.4-mini", "GPT-5.4 Mini"},
      {"gpt-5.3-codex", "GPT-5.3 Codex"},
      {"gpt-5.2-codex", "GPT-5.2 Codex"},
      {"gpt-5.2", "GPT-5.2"},
      {"gpt-5.1-codex-max", "GPT-5.1 Codex Max"},
      {"gpt-5.1-codex-mini", "GPT-5.1 Codex Mini"}
    ]
  end

  @doc """
  Returns Codex models with metadata {value, label, description, color} tuples for UI displays.
  """
  def codex_models_with_meta do
    [
      {"gpt-5.5", "GPT-5.5", "Newest frontier · complex coding, computer use (default)",
       "text-warning"},
      {"gpt-5.4", "GPT-5.4", "Flagship frontier for professional work", "text-warning"},
      {"gpt-5.4-mini", "GPT-5.4 Mini", "Fast and cheap for subagents", "text-info"},
      {"gpt-5.3-codex", "GPT-5.3 Codex", "Industry-leading coding model", "text-info"},
      {"gpt-5.2-codex", "GPT-5.2 Codex", "Frontier Codex-optimized", "text-info"},
      {"gpt-5.2", "GPT-5.2", "Long-running agents", "text-info"},
      {"gpt-5.1-codex-max", "GPT-5.1 Codex Max", "Deep reasoning, large context", "text-success"},
      {"gpt-5.1-codex-mini", "GPT-5.1 Codex Mini", "Cheaper and faster", "text-success"}
    ]
  end

  @doc "Discovered Pi model slugs from the cache. Never calls the harness."
  @spec pi_models() :: {[String.t()], :fresh | :stale | :empty}
  def pi_models do
    case EyeInTheSky.Pi.ModelDiscoveryCache.get_cached() do
      {:ok, models, freshness} -> {Enum.map(models, & &1["id"]), freshness}
      :empty -> {[], :empty}
    end
  end

  @doc """
  Returns {value, label} tuples for the given provider.

  Pi returns `{slug, slug}` for every discovered model — the slug doubles as
  the human label because harness-discovered ids have no separate display
  name. This matches the documented shape so destructuring consumers (see
  `new_session_modal.ex:436`) don't crash on the Pi optgroup.
  """
  def models_for_provider("codex"), do: codex_models()

  def models_for_provider("pi") do
    {slugs, _freshness} = pi_models()
    Enum.map(slugs, &{&1, &1})
  end

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
      "sonnet" -> "claude-sonnet-5"
      "opus" -> "claude-opus-4-8"
      _ -> model
    end
  end

  def normalize_model_alias(nil), do: "claude-sonnet-5"

  @doc """
  Returns the default model slug for a provider.
  """
  def default_model_for("codex"), do: "gpt-5.5"
  def default_model_for("pi"), do: nil
  def default_model_for(_), do: "claude-opus-4-8"

  @doc """
  Returns a human-readable display name for any supported model slug,
  including backward-compat short aliases. Falls back to the slug itself.
  """
  def model_display_name(slug) when is_binary(slug) do
    case Enum.find(claude_models() ++ codex_models(), fn {val, _} ->
           val == slug
         end) do
      {_, label} -> label
      nil -> short_alias_display(slug)
    end
  end

  def model_display_name(other), do: to_string(other)

  @doc """
  Ensures `current_slug` always appears in `entries`, synthesizing a
  `group: "Current"` entry if it's absent from every known list (the
  `sonnet-4-6`-style stale/custom case — spec §4.3). Idempotent.
  """
  @spec entries_with_current([EyeInTheSky.ModelEntry.t()], String.t(), String.t()) :: [
          EyeInTheSky.ModelEntry.t()
        ]
  def entries_with_current(entries, provider, current_slug) do
    if Enum.any?(entries, &(&1.slug == current_slug)) do
      entries
    else
      entries ++
        [
          %EyeInTheSky.ModelEntry{
            provider: provider,
            slug: current_slug,
            label: current_slug,
            group: "Current",
            sub_provider: nil,
            premium?: false,
            legacy?: false,
            default?: false
          }
        ]
    end
  end

  defp short_alias_display("opus"), do: "Opus 4.8"
  defp short_alias_display("opus[1m]"), do: "Opus (1M)"
  defp short_alias_display("sonnet"), do: "Sonnet 5"
  defp short_alias_display("sonnet[1m]"), do: "Sonnet (1M)"
  defp short_alias_display("haiku"), do: "Haiku 4.5"
  defp short_alias_display("claude-opus-4-6"), do: "Opus 4.6"
  defp short_alias_display(other), do: other
end
