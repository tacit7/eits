defmodule EyeInTheSky.Messages do
  @moduledoc """
  The Messages context for managing agent-user messaging.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Messages.Aggregations
  alias EyeInTheSky.Messages.ChannelMessageNumbering
  alias EyeInTheSky.Messages.Deduplicator
  alias EyeInTheSky.Messages.JsonlStorage
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Messages.StatusManager
  alias EyeInTheSky.QueryHelpers
  alias EyeInTheSky.Repo
  require Logger

  @doc """
  Returns the list of messages.
  """
  @spec list_messages() :: [Message.t()]
  def list_messages do
    Repo.all(Message)
  end

  @doc """
  Returns messages for a session. Delegates to list_messages_for_session/2 with no project_id.
  """
  @spec list_messages_for_session(integer()) :: [Message.t()]
  def list_messages_for_session(session_id) do
    list_messages_for_session(session_id, nil)
  end

  @doc """
  Returns messages for a session.

  Two storage backends are supported:
  - JSONL: used when `project_id` is a binary string (reads from
    `~/.claude/projects/{project_id}/{session_id}.jsonl`, falls back to DB if empty).
  - Database: used when `project_id` is nil or any non-binary value.
  """
  def list_messages_for_session(session_id, project_id) do
    load_messages(session_id, project_id)
  end

  # Reads from JSONL storage; falls back to DB when the file is empty.
  defp load_messages(session_id, project_id) when is_binary(project_id) do
    Logger.debug("Loading messages from JSONL for session: #{session_id}, project: #{project_id}")

    case JsonlStorage.read_session_messages(project_id, session_id) do
      [] ->
        Logger.debug("No messages found in JSONL file, falling back to database")
        list_messages_for_session_db(session_id)

      messages ->
        Logger.debug("Loaded #{length(messages)} messages from JSONL file")
        messages
    end
  end

  defp load_messages(session_id, _), do: list_messages_for_session_db(session_id)

  defp list_messages_for_session_db(session_id) do
    QueryHelpers.for_session_direct(Message, session_id, order_by: [asc: :inserted_at])
  end

  @doc """
  Returns the list of messages for a specific channel.
  """
  def list_messages_for_channel(channel_id) do
    Message
    |> where([m], m.channel_id == ^channel_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
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
  @spec get_message!(integer()) :: Message.t()
  def get_message!(id) do
    Repo.get!(Message, id)
  end

  @doc """
  Gets a message by ID, returning {:ok, message} or {:error, :not_found}.
  """
  @spec get_message(integer()) :: {:ok, Message.t()} | {:error, :not_found}
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
  Returns a MapSet of source_uuids (from the provided list) that already exist in the DB
  for the given session. Used by BulkImporter to fast-path dedup without per-row SELECTs.
  """
  @spec existing_source_uuids(integer(), list(String.t())) :: MapSet.t()
  def existing_source_uuids(_session_id, []), do: MapSet.new()

  def existing_source_uuids(session_id, source_uuids) when is_list(source_uuids) do
    Message
    |> where([m], m.session_id == ^session_id and m.source_uuid in ^source_uuids)
    |> select([m], m.source_uuid)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Creates a message (plain insert without advisory lock).
  For channel messages with sequential numbering, use create_channel_message/1.
  """
  @spec create_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create_message(attrs \\ %{}) do
    attrs = message_defaults(attrs)

    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a channel message with auto-assigned sequential numbering.
  Uses an advisory lock to prevent duplicate channel_message_numbers under concurrent inserts.
  """
  @spec create_channel_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create_channel_message(attrs \\ %{}) do
    attrs = message_defaults(attrs)

    cid = Map.get(attrs, :channel_id)
    has_number = Map.get(attrs, :channel_message_number)

    if not is_nil(cid) && is_nil(has_number) do
      # Advisory lock on the channel prevents two concurrent inserts from reading
      # the same MAX and assigning duplicate channel_message_numbers.
      ChannelMessageNumbering.create(cid, attrs)
    else
      %Message{}
      |> Message.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Sends a message (creates an outbound message).
  """
  @spec send_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_message(attrs) do
    attrs
    |> Map.put(:direction, "outbound")
    |> Map.put(:status, "pending")
    |> create_message()
    |> broadcast_and_return()
  end

  @doc """
  Records an incoming reply (creates an inbound message).
  """
  def record_incoming_reply(session_id, provider, body, opts \\ []) do
    id = Keyword.get(opts, :id) || Ecto.UUID.generate()
    source_uuid = Keyword.get(opts, :source_uuid) || Ecto.UUID.generate()
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

    attrs =
      attrs
      |> then(fn a -> if channel_id, do: Map.put(a, :channel_id, channel_id), else: a end)
      |> message_defaults()

    Deduplicator.find_or_create(attrs, metadata)
    |> broadcast_and_return()
  end

  @doc """
  Updates a message.
  """
  @spec update_message(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
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
  @spec delete_message(Message.t()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def delete_message(%Message{} = message) do
    Repo.delete(message)
  end

  @doc """
  Deletes all messages for a session.
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
  Returns the total cost in USD for all messages in a session.
  """
  defdelegate total_cost_for_session(session_id), to: Aggregations

  @doc """
  Returns the total token count (input + output) for all messages in a session.
  """
  defdelegate total_tokens_for_session(session_id), to: Aggregations

  @doc """
  Returns recent messages for a session (default last 50).
  """
  def list_recent_messages(session_id, limit \\ 50)

  def list_recent_messages(session_id, limit) do
    Message
    |> where([m], m.session_id == ^session_id)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload(:attachments)
    |> Enum.reverse()
    |> Deduplicator.deduplicate_by_source_uuid()
  end

  @doc """
  Searches messages for a session by body content using case-insensitive substring match.
  Returns up to 100 results ordered chronologically.
  """
  @spec search_messages_for_session(integer(), String.t()) :: [Message.t()]
  def search_messages_for_session(session_id, query) when is_binary(query) and query != "" do
    pattern = "%#{query}%"

    Message
    |> where([m], m.session_id == ^session_id)
    |> where([m], ilike(m.body, ^pattern))
    |> order_by([m], asc: m.inserted_at)
    |> limit(100)
    |> Repo.all()
    |> Repo.preload(:attachments)
    |> Deduplicator.deduplicate_by_source_uuid()
  end

  def search_messages_for_session(session_id, _query) do
    list_recent_messages(session_id)
  end

  @doc """
  Cross-session full-text search across session messages.

  Options:
    - `:session_id` - integer session ID to scope results (optional)
    - `:limit` - max results to return (default 10, max 100)

  Returns list of maps with keys: id, session_id, session_uuid, sender_role, body_excerpt, inserted_at.
  Uses the GIN index on messages_body_fts for efficient FTS. Falls back to ILIKE on error.
  """
  @spec search_messages(String.t(), keyword()) :: [map()]
  def search_messages(query, opts \\ [])

  def search_messages(query, opts) when is_binary(query) and query != "" do
    limit = min(Keyword.get(opts, :limit, 10), 100)
    session_id = Keyword.get(opts, :session_id)

    base =
      from(m in Message,
        join: s in EyeInTheSky.Sessions.Session,
        on: m.session_id == s.id,
        where: not is_nil(m.session_id),
        where: m.sender_role in ["user", "agent", "assistant"],
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        select: %{
          id: m.id,
          session_id: m.session_id,
          session_uuid: s.uuid,
          session_name: s.name,
          sender_role: m.sender_role,
          body: m.body,
          inserted_at: m.inserted_at
        }
      )

    base =
      if session_id do
        where(base, [m], m.session_id == ^session_id)
      else
        base
      end

    fts_query =
      where(
        base,
        [m],
        fragment(
          "to_tsvector('english', COALESCE(?, '')) @@ plainto_tsquery('english', ?)",
          m.body,
          ^query
        )
      )

    results =
      case Repo.all(fts_query) do
        [] ->
          pattern = "%#{query}%"

          ilike_query = where(base, [m], ilike(m.body, ^pattern))
          Repo.all(ilike_query)

        rows ->
          rows
      end

    Enum.map(results, fn row ->
      %{
        id: row.id,
        session_id: row.session_id,
        session_uuid: row.session_uuid,
        session_name: row.session_name,
        sender_role: row.sender_role,
        body_excerpt: String.slice(row.body || "", 0, 200),
        inserted_at: row.inserted_at
      }
    end)
  end

  def search_messages(_query, _opts), do: []

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

  @doc """
  Counts messages for a session.
  """
  @spec count_messages_for_session(integer()) :: non_neg_integer()
  def count_messages_for_session(session_id) do
    QueryHelpers.count_for_session(Message, session_id)
  end

  @doc """
  Deletes messages for a session beyond the given index (keeps the N oldest).
  Returns the number of deleted rows.
  """
  def truncate_messages_after_index(session_id, keep_count)
      when is_integer(keep_count) and keep_count >= 0 do
    # Find the ID of the Nth oldest message to use as a cutoff
    cutoff_id =
      Message
      |> where([m], m.session_id == ^session_id)
      |> order_by([m], asc: m.id)
      |> offset(^keep_count)
      |> limit(1)
      |> select([m], m.id)
      |> Repo.one()

    if cutoff_id do
      {deleted, _} =
        Message
        |> where([m], m.session_id == ^session_id and m.id >= ^cutoff_id)
        |> Repo.delete_all()

      deleted
    else
      0
    end
  end

  @doc """
  Finds an existing message with nil source_uuid matching session, role, and body.
  Used exclusively by BulkImporter to link session-file entries to pre-existing rows
  that were written before a source_uuid was available.
  Returns {:ok, message} or :not_found.
  """
  def find_unlinked_import_candidate(session_id, sender_role, body) do
    case Deduplicator.find_recent_message(session_id, body,
           sender_role: sender_role,
           require_nil_source_uuid: true,
           max_age_seconds: 86_400
         ) do
      nil -> :not_found
      message -> {:ok, message}
    end
  end

  @doc """
  Returns an existing DM message with the same body sent to the same session within
  the given window (default 30 seconds). Used for idempotency on DM creation.
  """
  def find_recent_dm(session_id, body, opts \\ []) do
    seconds = Keyword.get(opts, :seconds, 30)

    Deduplicator.find_recent_message(session_id, body,
      sender_role: "agent",
      max_age_seconds: seconds
    )
  end

  defp message_defaults(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs
    |> Map.put_new(:uuid, Ecto.UUID.generate())
    |> Map.put_new(:inserted_at, now)
    |> Map.put_new(:updated_at, now)
  end

  defp broadcast_and_return({:ok, message}) do
    try do
      if message.channel_id do
        EyeInTheSky.Events.channel_message(message.channel_id, message)
      else
        EyeInTheSky.Events.session_new_message(message.session_id, message)
      end
    rescue
      e -> Logger.error("broadcast failed for message #{message.id}: #{Exception.message(e)}")
    end

    {:ok, message}
  end

  defp broadcast_and_return(error), do: error

  @doc """
  Returns true when a session already has at least one inbound reply
  for the given provider.

  Used to decide if the next prompt should resume an existing conversation.
  """
  @spec has_inbound_reply?(integer(), String.t()) :: boolean()
  def has_inbound_reply?(session_id, provider) when is_binary(provider) do
    Message
    |> where(
      [m],
      m.session_id == ^session_id and m.direction == "inbound" and m.provider == ^provider
    )
    |> Repo.exists?()
  end

  def has_inbound_reply?(session_id, _provider), do: has_inbound_reply?(session_id, "claude")

  @doc """
  Returns true when a session already has at least one inbound Claude reply.

  Used to decide if the next prompt should resume an existing Claude conversation.
  """
  def has_inbound_claude_reply?(session_id) do
    has_inbound_reply?(session_id, "claude")
  end

  @doc """
  Returns the most recent inbound DMs received by a session, oldest-first.
  """
  @spec list_inbound_dms(integer(), pos_integer()) :: [Message.t()]
  def list_inbound_dms(session_id, limit \\ 20, opts \\ []) when is_integer(session_id) do
    from_id = Keyword.get(opts, :from_session_id)

    query =
      Message
      |> where([m], m.to_session_id == ^session_id)
      |> where([m], not is_nil(m.from_session_id))

    query =
      if from_id do
        where(query, [m], m.from_session_id == ^from_id)
      else
        query
      end

    query
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
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

  @doc "Marks a message as processing. No-op if message_id is nil."
  defdelegate mark_processing(message_id), to: StatusManager

  @doc "Marks a message as delivered. No-op if message_id is nil."
  defdelegate mark_delivered(message_id), to: StatusManager

  @doc "Marks a message as failed with a reason. No-op if message_id is nil."
  defdelegate mark_failed(message_id, reason), to: StatusManager
end
