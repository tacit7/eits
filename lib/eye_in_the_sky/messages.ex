defmodule EyeInTheSky.Messages do
  @moduledoc """
  The Messages context for managing agent-user messaging.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Messages.JsonlStorage
  alias EyeInTheSky.QueryHelpers
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
  Returns the list of messages for a specific session from JSONL file or database.
  If project_id is provided, loads from JSONL file (~/.claude/projects/{projectId}/{sessionId}.jsonl).
  Otherwise, falls back to database query.
  """
  def list_messages_for_session(session_id, project_id) when is_binary(project_id) do
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
  Creates a message.
  """
  @spec create_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create_message(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      %{inserted_at: now, updated_at: now}
      |> Map.merge(attrs)

    # Auto-assign channel_message_number for channel messages
    # Handles both atom and string key maps
    cid = Map.get(attrs, :channel_id) || Map.get(attrs, "channel_id")

    has_number =
      Map.get(attrs, :channel_message_number) || Map.get(attrs, "channel_message_number")

    if cid && is_nil(has_number) do
      # Advisory lock on the channel prevents two concurrent inserts from reading
      # the same MAX and assigning duplicate channel_message_numbers.
      Repo.transaction(fn ->
        lock_key = :erlang.phash2(cid)
        Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])

        attrs = Map.put(attrs, :channel_message_number, next_channel_message_number(cid))

        case %Message{}
             |> Message.changeset(attrs)
             |> Repo.insert() do
          {:ok, message} -> message
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    else
      %Message{}
      |> Message.changeset(attrs)
      |> Repo.insert()
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

  @doc """
  Sends a message (creates an outbound message).
  """
  @spec send_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_message(attrs) do
    attrs
    |> Map.put(:uuid, Ecto.UUID.generate())
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
      cond do
        source_uuid && message_exists_by_source_uuid?(source_uuid) ->
          # Already recorded by source_uuid — enrich with metadata if provided
          # (session file sync imports messages without usage data; later calls
          # may enrich with usage metadata using the same source_uuid)
          existing = Repo.get_by!(Message, source_uuid: source_uuid)
          maybe_enrich_metadata(existing, metadata)

        is_nil(source_uuid) ->
          # No source_uuid — check for a recent message with same content to avoid
          # duplicating a message already imported from the session file via periodic sync.
          case find_recent_agent_message(session_id, body) do
            nil -> create_message(attrs)
            existing -> maybe_enrich_metadata(existing, metadata)
          end

        true ->
          create_message(attrs)
      end

    result |> broadcast_and_return()
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

  @doc """
  Returns recent messages for a session (default last 50).
  """
  def list_recent_messages(session_id, limit \\ 50)

  def list_recent_messages(session_id, limit) do
    Message
    |> where([m], m.session_id == ^session_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload(:attachments)
    |> Enum.reverse()
    |> deduplicate_by_source_uuid()
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
    |> deduplicate_by_source_uuid()
  end

  def search_messages_for_session(session_id, _query) do
    list_recent_messages(session_id)
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
  Used to link messages created before sync (e.g. via send_message or save_result)
  with their corresponding session file entry, preventing duplicates.
  Returns {:ok, message} or :not_found.
  """
  def find_unlinked_message(session_id, sender_role, body) do
    one_minute_ago =
      DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

    Message
    |> where(
      [m],
      m.session_id == ^session_id and
        m.sender_role == ^sender_role and
        is_nil(m.source_uuid) and
        m.body == ^body and
        m.inserted_at >= ^one_minute_ago
    )
    |> order_by([m], desc: m.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> :not_found
      message -> {:ok, message}
    end
  end

  defp broadcast_and_return({:ok, message}) do
    EyeInTheSky.Events.session_new_message(message.session_id, message)

    if message.channel_id do
      EyeInTheSky.Events.channel_message(message.channel_id, message)
    end

    {:ok, message}
  end

  defp broadcast_and_return(error), do: error

  # Finds the most recent agent message in the session matching the given body,
  defp maybe_enrich_metadata(message, metadata) do
    if metadata && metadata != %{} do
      update_message(message, %{metadata: metadata})
    else
      {:ok, message}
    end
  end

  # within the last minute. Used to detect duplicates before creating a new record.
  # Unlike find_unlinked_message, this does NOT filter on is_nil(source_uuid) because
  # a concurrent sync may have already stamped the source_uuid on an existing message.
  defp find_recent_agent_message(session_id, body) do
    one_minute_ago =
      DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

    Message
    |> where(
      [m],
      m.session_id == ^session_id and
        m.sender_role == "agent" and
        m.body == ^body and
        m.inserted_at >= ^one_minute_ago
    )
    |> order_by([m], desc: m.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

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
  Used by EITS-CMD `dm list` to inject recent context back into an agent.
  """
  @spec list_inbound_dms(integer(), pos_integer()) :: [Message.t()]
  def list_inbound_dms(session_id, limit \\ 20) when is_integer(session_id) do
    Message
    |> where([m], m.to_session_id == ^session_id)
    |> where([m], not is_nil(m.from_session_id))
    |> order_by([m], [desc: m.inserted_at, desc: m.id])
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

end
