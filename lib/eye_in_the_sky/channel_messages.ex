defmodule EyeInTheSky.ChannelMessages do
  @moduledoc """
  Context for channel-scoped messages, thread replies, and threading support.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Repo

  @doc """
  Returns the list of messages for a specific channel.

  Options:
    - `:limit` — max number of messages to return, default 100
    - `:before_id` — return only messages with id < before_id (cursor pagination)

  Results are returned in chronological order (oldest first).
  """
  def list_messages_for_channel(channel_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    before_id = Keyword.get(opts, :before_id)

    Message
    |> where([m], m.channel_id == ^channel_id and is_nil(m.parent_message_id))
    |> then(fn q ->
      if before_id, do: where(q, [m], m.id < ^before_id), else: q
    end)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> preload([:reactions, :attachments, :session])
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Creates a channel message.
  """
  def create_channel_message(attrs) do
    attrs
    |> Map.put(:uuid, Ecto.UUID.generate())
    |> EyeInTheSky.Messages.create_channel_message()
  end

  @doc """
  Sends a message to a channel (creates an outbound message).
  """
  def send_channel_message(attrs) do
    result =
      attrs
      |> Map.put(:uuid, Ecto.UUID.generate())
      |> Map.put(:direction, "outbound")
      |> Map.put(:status, "pending")
      |> EyeInTheSky.Messages.create_channel_message()

    # broadcast_and_return in Messages.create_channel_message already fires
    # Events.channel_message — no explicit re-broadcast needed here.
    result
  end

  @doc """
  Returns thread replies for a parent message.
  """
  def list_thread_replies(parent_message_id) do
    Message
    |> where([m], m.parent_message_id == ^parent_message_id)
    |> order_by([m], asc: m.inserted_at)
    |> preload([:reactions, :attachments])
    |> Repo.all()
  end

  @doc """
  Creates a thread reply.
  """
  def create_thread_reply(parent_message_id, attrs) do
    attrs = Map.put(attrs, :parent_message_id, parent_message_id)

    with {:ok, message} <- create_channel_message(attrs) do
      increment_thread_count(parent_message_id)
      {:ok, message}
    end
  end

  @doc """
  Increments the thread reply count for a parent message.
  """
  def increment_thread_count(parent_message_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(m in Message,
      where: m.id == ^parent_message_id
    )
    |> Repo.update_all(
      inc: [thread_reply_count: 1],
      set: [last_thread_reply_at: now]
    )
  end

  @doc """
  Gets a message with its thread replies loaded.
  """
  def get_message_with_thread!(id) do
    Message
    |> where([m], m.id == ^id)
    |> preload([:thread_replies, :reactions, :attachments])
    |> Repo.one!()
  end
end
