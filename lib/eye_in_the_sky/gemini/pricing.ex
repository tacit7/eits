defmodule EyeInTheSky.Gemini.Pricing do
  @moduledoc """
  Per-model USD pricing for Gemini API usage.

  Gemini's SDK does not return cost in its `ResultEvent.stats` — only token
  counts. To match the parity Claude/Codex have in the DM metrics footer,
  we compute `total_cost_usd` from `tokens_in × input_rate + tokens_out ×
  output_rate` using the table below.

  Rates are USD per **one million** tokens, sourced from Google's published
  Gemini API pricing as of 2025-05. Keep this table up to date — drift
  here silently misreports per-message cost across the UI and aggregates.

  ## Tiered models (gemini-2.5-pro)

  Pro has a 2× price step above 200k input tokens. We use the cheaper
  tier by default; pass the input token count to `cost/3` to apply the
  tier correctly.
  """

  # {input $/1M, output $/1M}
  @rates %{
    # Pro: $1.25 / $10 below 200k, $2.50 / $15 above
    "gemini-2.5-pro" => {1.25, 10.0},
    "gemini-2.5-flash" => {0.30, 2.50},
    "gemini-2.5-flash-lite" => {0.10, 0.40}
  }

  @pro_high_tier {2.50, 15.0}
  @pro_threshold 200_000

  @doc """
  Returns the {input_rate, output_rate} pair (USD per 1M tokens) for a model
  given an input token count. Returns `nil` for unknown models.
  """
  @spec rates(String.t() | nil, non_neg_integer()) :: {float(), float()} | nil
  def rates(nil, _input_tokens), do: nil

  def rates("gemini-2.5-pro", input_tokens) when input_tokens > @pro_threshold,
    do: @pro_high_tier

  def rates(model, _input_tokens), do: Map.get(@rates, model)

  @doc """
  Compute `total_cost_usd` from token counts and model.

  Returns `nil` if the model isn't priced, or if either token count is
  missing. Always rounds to 6 decimal places to keep DB rows compact and
  rendering stable.
  """
  @spec cost(String.t() | nil, non_neg_integer() | nil, non_neg_integer() | nil) ::
          float() | nil
  def cost(model, input_tokens, output_tokens)
      when is_integer(input_tokens) and is_integer(output_tokens) do
    case rates(model, input_tokens) do
      {input_rate, output_rate} ->
        usd = input_tokens * input_rate / 1_000_000 + output_tokens * output_rate / 1_000_000
        Float.round(usd, 6)

      nil ->
        nil
    end
  end

  def cost(_model, _input, _output), do: nil

  @doc """
  Convenience: return a model_usage map (mirrors Claude's metadata.model_usage
  shape so the existing DM metrics renderer fallback paths work without a
  schema change).
  """
  @spec model_usage(String.t() | nil, non_neg_integer() | nil, non_neg_integer() | nil) ::
          map() | nil
  def model_usage(nil, _input, _output), do: nil

  def model_usage(model, input_tokens, output_tokens) do
    case cost(model, input_tokens, output_tokens) do
      nil ->
        nil

      usd ->
        %{
          model => %{
            "costUSD" => usd,
            "inputTokens" => input_tokens || 0,
            "outputTokens" => output_tokens || 0
          }
        }
    end
  end
end
