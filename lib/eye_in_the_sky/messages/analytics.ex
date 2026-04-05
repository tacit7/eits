defmodule EyeInTheSky.Messages.Analytics do
  @moduledoc """
  Aggregation queries for message cost and token analytics per session.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Repo

  @doc """
  Returns the total cost in USD for all messages in a session.
  """
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
