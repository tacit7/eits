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
    [
      "gpt-5.5",
      "gpt-5.4",
      "gpt-5.4-mini",
      "gpt-5.3-codex",
      "gpt-5.2-codex",
      "gpt-5.2",
      "gpt-5.1-codex-max",
      "gpt-5.1-codex-mini",
      # backward compat for sessions spawned before the unified list
      "gpt-5.1",
      "gpt-5-codex-mini"
    ]
  end

  @doc """
  Returns the default model slug for a provider (Codex).
  Claude defaults remain in the caller (SpawnValidator) to preserve backward-compat
  API behavior — spawning a Claude agent with no model still resolves to "haiku".
  Pi has no default — model must be specified explicitly (resolved from discovery in Phase 2).
  """
  def default_model("codex"), do: "gpt-5.5"
  def default_model("pi"), do: nil

  # Pi models are format-validated ("<pi-provider>/<model-id>"); the true list
  # comes from Pi model discovery (Phase 2). Model id may itself contain "/".
  @pi_model_regex ~r{^[A-Za-z0-9_.-]+/[A-Za-z0-9_.:/@+-]+$}

  @doc "Validates a model for a provider: format-based for pi, list-based otherwise."
  def valid_model?("pi", model) when is_binary(model), do: Regex.match?(@pi_model_regex, model)
  def valid_model?("pi", _), do: false
  def valid_model?(provider, model), do: model in valid_model_slugs(provider)

  @doc "Splits a pi model into {pi_provider, model_id} on the FIRST slash only."
  def pi_split_model!(model) when is_binary(model) do
    [provider, model_id] = String.split(model, "/", parts: 2)
    {provider, model_id}
  end

  @doc """
  Returns a flat list of valid model slugs for the given provider.
  """
  def valid_model_slugs(provider)
  def valid_model_slugs("codex"), do: codex_models()
  def valid_model_slugs(_), do: claude_models()

  @doc """
  Returns a map of provider => model validation spec.
  For claude/codex: list of valid model slugs.
  For pi: :format_validated (format-regex validated, not a list).
  """
  def valid_model_combos do
    %{
      "claude" => valid_model_slugs("claude"),
      "codex" => valid_model_slugs("codex"),
      "pi" => :format_validated
    }
  end
end
