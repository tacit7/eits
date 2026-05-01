defmodule EyeInTheSky.Messages.Listings do
  @moduledoc false

  import Ecto.Query, warn: false
  alias EyeInTheSky.Messages.Deduplicator
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.QueryHelpers
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Search.PgSearch

  @spec list_messages_for_channel(String.t()) :: [Message.t()]
  def list_messages_for_channel(channel_id) do
    Message
    |> where([m], m.channel_id == ^channel_id)
    |> order_by([m], asc: m.inserted_at)
    |> limit(500)
    |> Repo.all()
  end

  def list_recent_messages(session_id, limit \\ 50)

  def list_recent_messages(session_id, limit) do
    Message
    |> where([m], m.session_id == ^session_id)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> preload(:attachments)
    |> Repo.all()
    |> Enum.reverse()
    |> Deduplicator.deduplicate_by_source_uuid()
  end

  @spec search_messages_for_session(integer(), String.t()) :: [Message.t()]
  def search_messages_for_session(session_id, query) when is_binary(query) and query != "" do
    pattern = "%#{query}%"

    fallback_query =
      Message
      |> where([m], m.session_id == ^session_id)
      |> where([m], ilike(m.body, ^pattern))
      |> order_by([m], asc: m.inserted_at)

    PgSearch.search(
      table: "messages",
      schema: Message,
      query: query,
      search_columns: ["body"],
      sql_filter: "AND m.session_id = $2",
      sql_params: [session_id],
      fallback_query: fallback_query,
      preload: [:attachments],
      limit: 100
    )
    |> Deduplicator.deduplicate_by_source_uuid()
  end

  def search_messages_for_session(session_id, _query), do: list_recent_messages(session_id)

  @spec list_inbound_dms(integer(), pos_integer(), keyword()) :: [Message.t()]
  def list_inbound_dms(session_id, limit \\ 20, opts \\ []) when is_integer(session_id) do
    from_id = Keyword.get(opts, :from_session_id)
    since = Keyword.get(opts, :since)

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

    query =
      if since do
        where(query, [m], m.inserted_at > ^since)
      else
        query
      end

    query
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
  end

  def list_pending_messages(session_id) do
    Message
    |> where([m], m.session_id == ^session_id and m.status == "pending")
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

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

  @spec count_messages_for_session(integer()) :: non_neg_integer()
  def count_messages_for_session(session_id) do
    QueryHelpers.count_for_session(Message, session_id)
  end

  def truncate_messages_after_index(session_id, keep_count)
      when is_integer(keep_count) and keep_count >= 0 do
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

  def find_recent_dm(session_id, body, opts \\ []) do
    seconds = Keyword.get(opts, :seconds, 30)

    Deduplicator.find_recent_message(session_id, body,
      sender_role: "agent",
      max_age_seconds: seconds
    )
  end

  @doc """
  H3 batch pre-fetch: returns a MapSet of agent-message bodies in this session
  within the given number of seconds. Used by BulkImporter to replace per-message
  dm_already_recorded? and agent_reply_already_recorded? SELECTs.
  """
  @spec recent_agent_bodies_for_session(integer(), keyword()) :: MapSet.t()
  def recent_agent_bodies_for_session(session_id, opts \\ []) do
    seconds = Keyword.get(opts, :seconds, 60)

    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-seconds, :second)
      |> DateTime.truncate(:second)

    Message
    |> where(
      [m],
      m.session_id == ^session_id and m.sender_role == "agent" and m.inserted_at >= ^cutoff
    )
    |> select([m], m.body)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  H3 batch pre-fetch: returns a map of {sender_role, body} -> Message for messages
  in this session that have no source_uuid and were inserted within the last 24h.
  Used by BulkImporter to replace per-message find_unlinked_import_candidate SELECTs.
  The most recent message wins when multiple rows share the same key.
  """
  @spec unlinked_candidates_map_for_session(integer()) :: %{{String.t(), String.t()} => Message.t()}
  def unlinked_candidates_map_for_session(session_id) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-86_400, :second)
      |> DateTime.truncate(:second)

    Message
    |> where([m], m.session_id == ^session_id and is_nil(m.source_uuid) and m.inserted_at >= ^cutoff)
    |> order_by([m], desc: m.inserted_at)
    |> Repo.all()
    |> Enum.reduce(%{}, fn msg, acc ->
      # Ordered desc, so the first occurrence per key is the most recent.
      Map.put_new(acc, {msg.sender_role, msg.body}, msg)
    end)
  end

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

  def has_inbound_claude_reply?(session_id), do: has_inbound_reply?(session_id, "claude")

  @spec existing_source_uuids(integer(), list(String.t())) :: MapSet.t()
  def existing_source_uuids(_session_id, []), do: MapSet.new()

  def existing_source_uuids(session_id, source_uuids) when is_list(source_uuids) do
    Message
    |> where([m], m.session_id == ^session_id and m.source_uuid in ^source_uuids)
    |> select([m], m.source_uuid)
    |> Repo.all()
    |> MapSet.new()
  end

  def get_last_source_uuid(session_id) do
    Message
    |> where([m], m.session_id == ^session_id and not is_nil(m.source_uuid))
    |> order_by([m], desc: m.inserted_at)
    |> limit(1)
    |> select([m], m.source_uuid)
    |> Repo.one()
  end
end
