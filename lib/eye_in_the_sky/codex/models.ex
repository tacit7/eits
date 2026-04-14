defmodule EyeInTheSky.Codex.Models do
  @moduledoc """
  Metadata for Codex-supported models.

  Context window sizes are sourced from official Codex documentation.
  Models without confirmed window sizes return nil — do not guess.
  """

  @context_windows %{
    "gpt-5.4" => 1_000_000,
    "gpt-5.3-codex" => 400_000,
    "gpt-5.2" => 400_000,
    "gpt-5.1-codex-max" => 400_000,
    "gpt-5.2-codex" => 400_000,
    "gpt-5.1-codex-mini" => 400_000
  }

  # Max output tokens per model (where known)
  @max_output_tokens %{
    "gpt-5.3-codex" => 128_000,
    "gpt-5.2" => 128_000,
    "gpt-5.1-codex-max" => 128_000,
    "gpt-5.2-codex" => 128_000,
    "gpt-5.1-codex-mini" => 128_000
  }

  @doc """
  Returns the context window size in tokens for the given model, or nil if unknown.

  ## Examples

      iex> EyeInTheSky.Codex.Models.context_window("gpt-5.4")
      1_000_000

      iex> EyeInTheSky.Codex.Models.context_window("gpt-5.3-codex")
      400_000
  """
  @spec context_window(String.t() | nil) :: pos_integer() | nil
  def context_window(model), do: Map.get(@context_windows, model)

  @doc """
  Calculates context utilization as a percentage (0–100), rounded to one decimal place.
  Returns nil if the model's context window is unknown.

  ## Examples

      iex> EyeInTheSky.Codex.Models.context_percent("gpt-5.4", 250_000)
      25.0

      iex> EyeInTheSky.Codex.Models.context_percent("gpt-5.3-codex", 50_000)
      12.5
  """
  @spec context_percent(String.t() | nil, non_neg_integer()) :: float() | nil
  def context_percent(model, input_tokens) do
    case context_window(model) do
      nil -> nil
      window -> Float.round(input_tokens / window * 100, 1)
    end
  end

  @doc """
  Returns the max output tokens for the given model, or nil if unknown.

  ## Examples

      iex> EyeInTheSky.Codex.Models.max_output_tokens("gpt-5.3-codex")
      128_000

      iex> EyeInTheSky.Codex.Models.max_output_tokens("gpt-5.4")
      nil
  """
  @spec max_output_tokens(String.t() | nil) :: pos_integer() | nil
  def max_output_tokens(model), do: Map.get(@max_output_tokens, model)
end
