defmodule EyeInTheSky.Messages.Aggregations do
  @moduledoc """
  Aggregate query helpers for the Messages context.

  Extracted from `EyeInTheSky.Messages` to keep the main context module focused
  on CRUD and lifecycle operations. `Messages` delegates the aggregation
  functions here; callers should continue to use the `Messages` public API.

  ## Caching strategy

  `total_tokens` and `total_cost_usd` are cached on the `sessions` table and
  incremented atomically each time a message with usage metadata is inserted.
  These functions read the cached value directly from the session row (O(1))
  and fall back to the full aggregate scan over `messages` only when the
  cached column is `nil` — which only happens for sessions created before the
  cache columns were added (migration `20260501110334`).
  """

  import Ecto.Query, warn: false

  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Repo

  @doc """
  Returns the total cost in USD for all messages in a session.

  Reads from the `sessions.total_cost_usd` cache column. Falls back to a
  full aggregate scan over `messages` when the cached value is `nil`
  (pre-cache sessions).
  """
  @spec total_cost_for_session(integer()) :: float()
  def total_cost_for_session(session_id) do
    case Repo.one(from s in Session, where: s.id == ^session_id, select: s.total_cost_usd) do
      nil -> aggregate_cost_for_session(session_id)
      cached -> cached
    end
  end

  @doc """
  Returns the total token count (input + output) for all messages in a session.

  Reads from the `sessions.total_tokens` cache column. Falls back to a full
  aggregate scan over `messages` when the cached value is `nil`
  (pre-cache sessions).
  """
  @spec total_tokens_for_session(integer()) :: non_neg_integer()
  def total_tokens_for_session(session_id) do
    case Repo.one(from s in Session, where: s.id == ^session_id, select: s.total_tokens) do
      nil -> aggregate_tokens_for_session(session_id)
      cached -> cached
    end
  end

  # ---------------------------------------------------------------------------
  # Fallback aggregate scans (used only for pre-cache sessions)
  # ---------------------------------------------------------------------------

  defp aggregate_cost_for_session(session_id) do
    Message
    |> where([m], m.session_id == ^session_id)
    |> select(
      [m],
      fragment("COALESCE(SUM(CAST(COALESCE(metadata->>'total_cost_usd', '0') AS FLOAT)), 0.0)")
    )
    |> Repo.one() || 0.0
  end

  defp aggregate_tokens_for_session(session_id) do
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
