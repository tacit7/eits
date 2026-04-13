defmodule EyeInTheSky.Messages.ChannelMessageNumbering do
  @moduledoc """
  Handles sequential numbering for channel messages using PostgreSQL advisory locks.

  Advisory locks prevent duplicate channel_message_numbers when multiple processes
  insert messages into the same channel concurrently.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Repo

  @doc """
  Inserts a channel message with an auto-assigned sequential number.

  Acquires a transaction-scoped advisory lock on the channel before reading
  MAX(channel_message_number) and inserting, preventing duplicate numbering
  under concurrent writes.

  Returns `{:ok, message}` or `{:error, changeset}`.
  """
  @spec create(integer() | binary(), map()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create(channel_id, attrs) do
    Repo.transaction(fn -> insert_with_advisory_lock(channel_id, attrs) end)
  end

  defp insert_with_advisory_lock(cid, attrs) do
    lock_key = :erlang.phash2(cid)
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])
    attrs = Map.put(attrs, :channel_message_number, next_channel_message_number(cid))

    case %Message{} |> Message.changeset(attrs) |> Repo.insert() do
      {:ok, message} -> message
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp next_channel_message_number(channel_id) do
    current_max =
      from(m in Message,
        where: m.channel_id == ^channel_id and not is_nil(m.channel_message_number),
        select: max(m.channel_message_number)
      )
      |> Repo.one()

    (current_max || 0) + 1
  end
end
