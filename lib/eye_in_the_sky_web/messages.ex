defmodule EyeInTheSkyWeb.Messages do
  @moduledoc """
  The Messages context for managing agent-user messaging.

  Supports both database storage and JSONL file storage (opcode-style).
  JSONL files are stored in ~/.claude/projects/{projectId}/{sessionId}.jsonl
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Messages.Message
  alias EyeInTheSkyWeb.Messages.JsonlStorage
  alias EyeInTheSkyWeb.QueryHelpers
  require Logger

  @doc """
  Returns the list of messages.
  """
  def list_messages do
    Repo.all(Message)
  end

  @doc """
  Returns the list of messages for a specific session from JSONL file (opcode-style).
  Falls back to database if file doesn't exist.
  """
  def list_messages_for_session(session_id) do
    list_messages_for_session(session_id, nil)
  end

  @doc """
  Returns the list of messages for a specific session from JSONL file or database.
  If project_id is provided, loads from JSONL file (~/.claude/projects/{projectId}/{sessionId}.jsonl).
  Otherwise, falls back to database query.
  """
  def list_messages_for_session(session_id, project_id) when is_binary(project_id) do
    Logger.debug("Loading messages from JSONL for session: #{session_id}, project: #{project_id}")

    case JsonlStorage.read_session_messages(project_id, session_id) do
      messages when is_list(messages) and length(messages) > 0 ->
        Logger.debug("Loaded #{length(messages)} messages from JSONL file")
        messages

      [] ->
        Logger.debug("No messages found in JSONL file, falling back to database")
        list_messages_for_session_db(session_id)

      nil ->
        list_messages_for_session_db(session_id)
    end
  end

  def list_messages_for_session(session_id, nil) do
    list_messages_for_session_db(session_id)
  end

  # Internal function: Returns the list of messages for a specific session from database.
  defp list_messages_for_session_db(session_id) do
    QueryHelpers.for_session_direct(Message, session_id, order_by: [asc: :inserted_at])
  end

  @doc """
  Returns the list of messages for a specific project.
  """
  def list_messages_for_project(project_id) do
    Message
    |> where([m], m.project_id == ^project_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single message.

  Raises `Ecto.NoResultsError` if the Message does not exist.
  """
  def get_message!(id) do
    Repo.get!(Message, id)
  end

  @doc """
  Gets a message by ID, returning {:ok, message} or {:error, :not_found}.
  """
  def get_message(id) do
    case Repo.get(Message, id) do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  @doc """
  Checks if a message with the given ID exists.
  """
  def message_exists?(id) do
    Message
    |> where([m], m.id == ^id)
    |> Repo.exists?()
  end

  @doc """
  Checks if a message with the given source_uuid exists.
  """
  def message_exists_by_source_uuid?(source_uuid) do
    Message
    |> where([m], m.source_uuid == ^source_uuid)
    |> Repo.exists?()
  end

  @doc """
  Gets a message by its source_uuid.
  Returns {:ok, message} or {:error, :not_found}.
  """
  def get_message_by_source_uuid(source_uuid) do
    case Repo.get_by(Message, source_uuid: source_uuid) do
      nil -> {:error, :not_found}
      message -> {:ok, Repo.preload(message, [:session, :reactions])}
    end
  end

  @doc """
  Gets a message by its uuid column.
  Returns {:ok, message} or {:error, :not_found}.
  """
  def get_message_by_uuid(uuid) do
    case Repo.get_by(Message, uuid: uuid) do
      nil -> {:error, :not_found}
      message -> {:ok, Repo.preload(message, [:session, :reactions])}
    end
  end

  @doc """
  Returns the most recent source_uuid for a session, used as sync cursor.
  """
  def get_last_source_uuid(session_id) do
    Message
    |> where([m], m.session_id == ^session_id and not is_nil(m.source_uuid))
    |> order_by([m], desc: m.inserted_at)
    |> limit(1)
    |> select([m], m.source_uuid)
    |> Repo.one()
  end

  @doc """
  Creates a message.
  """
  def create_message(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      %{inserted_at: now, updated_at: now}
      |> Map.merge(attrs)

    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Sends a message (creates an outbound message).
  """
  def send_message(attrs) do
    result =
      attrs
      |> Map.put(:uuid, Ecto.UUID.generate())
      |> Map.put(:direction, "outbound")
      |> Map.put(:status, "pending")
      |> create_message()

    case result do
      {:ok, message} ->
        # Broadcast new message to session topic
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "session:#{message.session_id}",
          {:new_message, message}
        )

        # Also broadcast to channel topic if this is a channel message
        if message.channel_id do
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "channel:#{message.channel_id}:messages",
            {:new_message, message}
          )
        end

        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Records an incoming reply (creates an inbound message).
  """
  def record_incoming_reply(session_id, provider, body, opts \\ []) do
    id = Keyword.get(opts, :id) || Ecto.UUID.generate()
    source_uuid = Keyword.get(opts, :source_uuid)
    metadata = Keyword.get(opts, :metadata, %{})
    channel_id = Keyword.get(opts, :channel_id)

    attrs = %{
      uuid: id,
      session_id: session_id,
      sender_role: "agent",
      recipient_role: "user",
      provider: provider,
      direction: "inbound",
      body: body,
      status: "delivered",
      source_uuid: source_uuid,
      metadata: metadata
    }

    attrs = if channel_id, do: Map.put(attrs, :channel_id, channel_id), else: attrs

    result =
      if source_uuid && message_exists_by_source_uuid?(source_uuid) do
        # Already recorded, return existing message
        {:ok, Repo.get_by!(Message, source_uuid: source_uuid)}
      else
        create_message(attrs)
      end

    case result do
      {:ok, message} ->
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "session:#{message.session_id}",
          {:new_message, message}
        )

        # Also broadcast to channel topic if this is a channel message
        if message.channel_id do
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "channel:#{message.channel_id}:messages",
            {:new_message, message}
          )
        end

        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Updates a message.
  """
  def update_message(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates message status.
  """
  def update_message_status(%Message{} = message, status) do
    update_message(message, %{status: status})
  end

  @doc """
  Deletes a message.
  """
  def delete_message(%Message{} = message) do
    Repo.delete(message)
  end

  @doc """
  Deletes all messages for a session. Used for full reload from JSONL file.
  """
  def delete_session_messages(session_id) do
    Message
    |> where([m], m.session_id == ^session_id)
    |> Repo.delete_all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking message changes.
  """
  def change_message(%Message{} = message, attrs \\ %{}) do
    Message.changeset(message, attrs)
  end

  @doc """
  Returns recent messages for a session (default last 50).
  """
  def list_recent_messages(session_id, limit \\ 50) do
    Message
    |> where([m], m.session_id == ^session_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
    |> deduplicate_by_source_uuid()
  end

  # Remove duplicate messages by source_uuid, keeping the first occurrence
  defp deduplicate_by_source_uuid(messages) do
    messages
    |> Enum.reduce({[], MapSet.new()}, fn msg, {acc, seen_uuids} ->
      if msg.source_uuid && MapSet.member?(seen_uuids, msg.source_uuid) do
        {acc, seen_uuids}
      else
        new_seen =
          if msg.source_uuid, do: MapSet.put(seen_uuids, msg.source_uuid), else: seen_uuids

        {[msg | acc], new_seen}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc """
  Returns conversation thread for a session with pagination.
  """
  def get_conversation_thread(session_id, opts \\ []) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 50)

    Message
    |> where([m], m.session_id == ^session_id)
    |> order_by([m], asc: m.inserted_at)
    |> offset(^offset)
    |> limit(^limit)
    |> Repo.all()
  end

  # JSONL File-based Storage Functions (opcode-style)

  @doc """
  Loads recent messages for a session from JSONL file.
  If project_id provided, loads from JSONL file. Otherwise uses database.
  """
  def list_recent_messages(session_id, limit, project_id) when is_binary(project_id) do
    Logger.debug("Loading recent messages from JSONL for session: #{session_id}, limit: #{limit}")

    messages = list_messages_for_session(session_id, project_id)

    messages
    |> Enum.sort_by(fn msg -> msg.inserted_at || DateTime.utc_now() end, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.reverse()
  end

  def list_recent_messages(session_id, limit) do
    list_recent_messages(session_id, limit, nil)
  end

  @doc """
  Appends a message to a session's JSONL file.
  """
  def append_to_jsonl(project_id, session_id, message_attrs) when is_binary(project_id) do
    Logger.debug("Appending message to JSONL: session=#{session_id}")

    JsonlStorage.append_message(project_id, session_id, message_attrs)
  end

  @doc """
  Writes all messages for a session to JSONL file.
  Useful for bulk initialization or migration from database to file storage.
  """
  def write_session_to_jsonl(project_id, session_id) when is_binary(project_id) do
    Logger.info(
      "Writing session messages to JSONL file: project=#{project_id}, session=#{session_id}"
    )

    messages = list_messages_for_session_db(session_id)
    JsonlStorage.write_session_messages(project_id, session_id, messages)
  end

  @doc """
  Gets the path to a session's JSONL file.
  """
  def get_session_jsonl_path(project_id, session_id) when is_binary(project_id) do
    JsonlStorage.get_session_file_path(project_id, session_id)
  end

  @doc """
  Counts messages for a session.
  """
  def count_messages_for_session(session_id) do
    QueryHelpers.count_for_session(Message, session_id)
  end

  @doc """
  Returns true when a session already has at least one inbound Claude reply.

  Used to decide if the next prompt should resume an existing Claude conversation.
  """
  def has_inbound_claude_reply?(session_id) do
    Message
    |> where(
      [m],
      m.session_id == ^session_id and m.direction == "inbound" and m.provider == "claude"
    )
    |> Repo.exists?()
  end

  @doc """
  Returns unread/pending messages for a session.
  """
  def list_pending_messages(session_id) do
    Message
    |> where([m], m.session_id == ^session_id and m.status == "pending")
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  # Channel-based messaging

  @doc """
  Returns the list of messages for a specific channel.
  """
  def list_messages_for_channel(channel_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    # Get the last N messages by ordering DESC, then reverse for chronological display
    Message
    |> where([m], m.channel_id == ^channel_id and is_nil(m.parent_message_id))
    |> order_by([m], desc: m.inserted_at)
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
    |> create_message()
  end

  @doc """
  Sends a message to a channel (creates an outbound message).
  """
  def send_channel_message(attrs) do
    attrs
    |> Map.put(:uuid, Ecto.UUID.generate())
    |> Map.put(:direction, "outbound")
    |> Map.put(:status, "pending")
    |> create_message()
  end

  # Threading support

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

  # Reactions support

  @doc """
  Adds a reaction to a message.
  """
  def add_reaction(message_id, session_id, emoji) do
    alias EyeInTheSkyWeb.Messages.MessageReaction

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      message_id: message_id,
      session_id: session_id,
      emoji: emoji,
      inserted_at: now
    }

    %MessageReaction{}
    |> MessageReaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Removes a reaction from a message.
  """
  def remove_reaction(message_id, session_id, emoji) do
    alias EyeInTheSkyWeb.Messages.MessageReaction

    from(r in MessageReaction,
      where: r.message_id == ^message_id and r.session_id == ^session_id and r.emoji == ^emoji
    )
    |> Repo.delete_all()
  end

  @doc """
  Lists all reactions for a message, grouped by emoji.
  """
  def list_reactions_for_message(message_id) do
    alias EyeInTheSkyWeb.Messages.MessageReaction

    from(r in MessageReaction,
      where: r.message_id == ^message_id,
      order_by: [asc: r.inserted_at]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.emoji)
    |> Enum.map(fn {emoji, reactions} ->
      %{
        emoji: emoji,
        count: length(reactions),
        session_ids: Enum.map(reactions, & &1.session_id)
      }
    end)
  end

  @doc """
  Toggles a reaction (adds if not present, removes if present).
  """
  def toggle_reaction(message_id, session_id, emoji) do
    alias EyeInTheSkyWeb.Messages.MessageReaction

    existing =
      from(r in MessageReaction,
        where: r.message_id == ^message_id and r.session_id == ^session_id and r.emoji == ^emoji
      )
      |> Repo.one()

    if existing do
      remove_reaction(message_id, session_id, emoji)
      {:ok, :removed}
    else
      case add_reaction(message_id, session_id, emoji) do
        {:ok, _reaction} -> {:ok, :added}
        error -> error
      end
    end
  end
end
