defmodule EyeInTheSky.Messages.Aggregations do
  @moduledoc """
  Aggregate query helpers for the Messages context.

  Extracted from `EyeInTheSky.Messages` to keep the main context module focused
  on CRUD and lifecycle operations. `Messages` delegates the aggregation
  functions here; callers should continue to use the `Messages` public API.
  """

  import Ecto.Query, warn: false

  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Repo

  @doc """
  Returns the total cost in USD for all messages in a session.
  """
  @spec total_cost_for_session(integer()) :: float()
  def total_cost_for_session(session_id) do
    Message
    |> where([m], m.session_id == ^session_id)
    |> select(
      [m],
      fragment("COALESCE(SUM(CAST(COALESCE(metadata->>'total_cost_usd', '0') AS FLOAT)), 0.0)")
    )
    |> Repo.one() || 0.0
  end

  @doc """
  Returns the total token count (input + output) for all messages in a session.
  """
  @spec total_tokens_for_session(integer()) :: non_neg_integer()
  def total_tokens_for_session(session_id) do
    Message
    |> where([m], m.session_id == ^session_id)
    |> select(
      [m],
      fragment(
        "COALESCE(SUM(CAST(COALESCE(metadata->'usage'->>'input_tokens', '0') AS INTEGER) + CAST(COALESCE(metadata->'usage'->>'output_tokens', '0') AS INTEGER)), 0)"
      )
    )
    |> Repo.one() || 0
  end
end
