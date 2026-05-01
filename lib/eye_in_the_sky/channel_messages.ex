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
    - `:before_id` — return only messages with id < before_id (scroll-up / load-older)
    - `:after_id` — return only messages with id > after_id (poll-forward / catch-up)

  When `:after_id` is set, results are ordered oldest-first (chronological catch-up).
  Otherwise results are returned in chronological order (oldest first).
  """
  def list_messages_for_channel(channel_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    before_id = Keyword.get(opts, :before_id)
    after_id = Keyword.get(opts, :after_id)

    Message
    |> where([m], m.channel_id == ^channel_id and is_nil(m.parent_message_id))
    |> then(fn q ->
      if before_id, do: where(q, [m], m.id < ^before_id), else: q
    end)
    |> then(fn q ->
      if after_id do
        q
        |> where([m], m.id > ^after_id)
        |> order_by([m], asc: m.id)
      else
        order_by(q, [m], desc: m.inserted_at, desc: m.id)
      end
    end)
    |> limit(^limit)
    |> preload([:reactions, :attachments, :session])
    |> Repo.all()
    |> then(fn msgs ->
      if after_id, do: msgs, else: Enum.reverse(msgs)
    end)
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
  Returns thread replies for a parent message. Default limit: 200.
  Pass `limit: n` to override.
  """
  def list_thread_replies(parent_message_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    Message
    |> where([m], m.parent_message_id == ^parent_message_id)
    |> order_by([m], asc: m.inserted_at)
    |> limit(^limit)
    |> preload([:reactions, :attachments])
    |> Repo.all()
  end

  @doc """
  Creates a thread reply.

  Both the insert and the thread count increment run in a single transaction so a
  failed increment cannot leave thread_reply_count and last_thread_reply_at stale.
  """
  def create_thread_reply(parent_message_id, attrs) do
    attrs = Map.put(attrs, :parent_message_id, parent_message_id)

    Repo.transaction(fn ->
      case create_channel_message(attrs) do
        {:ok, message} ->
          increment_thread_count(parent_message_id)
          message

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, message} -> {:ok, message}
      {:error, changeset} -> {:error, changeset}
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
