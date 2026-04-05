defmodule EyeInTheSky.Messages.StatusManager do
  @moduledoc """
  Status lifecycle operations for Messages: processing, delivered, failed.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Repo

  @doc """
  Marks a message as processing (worker has claimed it for execution).
  No-op if message_id is nil.
  """
  @spec mark_processing(integer() | nil) :: :ok
  def mark_processing(nil), do: :ok

  def mark_processing(message_id) do
    Message
    |> where([m], m.id == ^message_id)
    |> Repo.update_all(set: [status: "processing"])

    :ok
  end

  @doc """
  Marks a message as delivered (Claude completed the run successfully).
  No-op if message_id is nil.
  """
  @spec mark_delivered(integer() | nil) :: :ok
  def mark_delivered(nil), do: :ok

  def mark_delivered(message_id) do
    Message
    |> where([m], m.id == ^message_id)
    |> Repo.update_all(set: [status: "delivered"])

    :ok
  end

  @doc """
  Marks a message as failed with a reason (worker dropped it due to error).
  No-op if message_id is nil.
  """
  @spec mark_failed(integer() | nil, String.t()) :: :ok
  def mark_failed(nil, _reason), do: :ok

  def mark_failed(message_id, reason) when is_binary(reason) do
    Message
    |> where([m], m.id == ^message_id)
    |> Repo.update_all(set: [status: "failed", failure_reason: reason])

    :ok
  end
end
