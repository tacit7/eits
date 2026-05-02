defmodule EyeInTheSky.Messages do
  @moduledoc """
  The Messages context for managing agent-user messaging.

  Query/listing helpers live in `Messages.Listings`.
  Full-text search lives in `Messages.Search`.
  Status transitions live in `Messages.StatusManager`.
  Token/cost aggregations live in `Messages.Aggregations`.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Messages.Aggregations
  alias EyeInTheSky.Messages.ChannelMessageNumbering
  alias EyeInTheSky.Messages.Deduplicator
  alias EyeInTheSky.Messages.JsonlStorage
  alias EyeInTheSky.Messages.Listings
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Messages.Search
  alias EyeInTheSky.Messages.StatusManager
  alias EyeInTheSky.QueryHelpers
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Sessions
  require Logger

  # ---------------------------------------------------------------------------
  # Session-scoped message loading (JSONL-aware)
  # ---------------------------------------------------------------------------

  @spec list_messages_for_session(integer()) :: [Message.t()]
  def list_messages_for_session(session_id), do: list_messages_for_session(session_id, nil)

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

  # ---------------------------------------------------------------------------
  # Listing delegates → Messages.Listings
  # ---------------------------------------------------------------------------

  defdelegate list_messages_for_channel(channel_id), to: Listings
  defdelegate list_recent_messages(session_id, limit \\ 50), to: Listings
  defdelegate list_inbound_dms(session_id, limit \\ 20, opts \\ []), to: Listings
  defdelegate list_pending_messages(session_id), to: Listings
  defdelegate get_conversation_thread(session_id, opts \\ []), to: Listings
  defdelegate count_messages_for_session(session_id), to: Listings
  defdelegate truncate_messages_after_index(session_id, keep_count), to: Listings
  defdelegate find_unlinked_import_candidate(session_id, sender_role, body), to: Listings
  defdelegate find_recent_dm(session_id, body, opts \\ []), to: Listings
  defdelegate recent_agent_bodies_for_session(session_id, opts \\ []), to: Listings
  defdelegate unlinked_candidates_map_for_session(session_id), to: Listings
  defdelegate has_inbound_reply?(session_id, provider), to: Listings
  defdelegate has_inbound_claude_reply?(session_id), to: Listings
  defdelegate existing_source_uuids(session_id, source_uuids), to: Listings
  defdelegate get_last_source_uuid(session_id), to: Listings
  defdelegate search_messages_for_session(session_id, query), to: Listings

  # ---------------------------------------------------------------------------
  # Search delegate → Messages.Search
  # ---------------------------------------------------------------------------

  defdelegate search_messages(query, opts \\ []), to: Search

  # ---------------------------------------------------------------------------
  # Single-record lookups
  # ---------------------------------------------------------------------------

  @spec get_message!(integer()) :: Message.t()
  def get_message!(id), do: Repo.get!(Message, id)

  @spec get_message(integer()) :: {:ok, Message.t()} | {:error, :not_found}
  def get_message(id) do
    case Repo.get(Message, id) do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  def message_exists?(id) do
    Message |> where([m], m.id == ^id) |> Repo.exists?()
  end

  def message_exists_by_source_uuid?(source_uuid) do
    Message |> where([m], m.source_uuid == ^source_uuid) |> Repo.exists?()
  end

  def get_message_by_source_uuid(source_uuid) do
    case Repo.get_by(Message, source_uuid: source_uuid) do
      nil -> {:error, :not_found}
      message -> {:ok, Repo.preload(message, [:session, :reactions])}
    end
  end

  def get_message_by_uuid(uuid) do
    case Repo.get_by(Message, uuid: uuid) do
      nil -> {:error, :not_found}
      message -> {:ok, Repo.preload(message, [:session, :reactions])}
    end
  end

  # ---------------------------------------------------------------------------
  # Create / update / delete
  # ---------------------------------------------------------------------------

  @spec create_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create_message(attrs \\ %{}) do
    attrs = message_defaults(attrs)

    result = %Message{} |> Message.changeset(attrs) |> Repo.insert()

    with {:ok, message} <- result do
      maybe_increment_session_cache(message)
    end

    result
  end

  @spec create_channel_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create_channel_message(attrs \\ %{}) do
    attrs = message_defaults(attrs)
    cid = Map.get(attrs, :channel_id)
    has_number = Map.get(attrs, :channel_message_number)

    result =
      if not is_nil(cid) && is_nil(has_number) do
        ChannelMessageNumbering.create(cid, attrs)
      else
        %Message{} |> Message.changeset(attrs) |> Repo.insert()
      end

    with {:ok, message} <- result do
      maybe_increment_session_cache(message)
    end

    result
  end

  @spec send_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_message(attrs) do
    attrs
    |> Map.put(:direction, "outbound")
    |> Map.put(:status, "pending")
    |> create_message()
    |> broadcast_and_return()
  end

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

  @spec update_message(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def update_message(%Message{} = message, attrs) do
    message |> Message.changeset(attrs) |> Repo.update()
  end

  def update_message_status(%Message{} = message, status) do
    update_message(message, %{status: status})
  end

  @spec delete_message(Message.t()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def delete_message(%Message{} = message), do: Repo.delete(message)

  def delete_session_messages(session_id) do
    Message |> where([m], m.session_id == ^session_id) |> Repo.delete_all()
  end

  def change_message(%Message{} = message, attrs \\ %{}) do
    Message.changeset(message, attrs)
  end

  # ---------------------------------------------------------------------------
  # Aggregation / status delegates
  # ---------------------------------------------------------------------------

  defdelegate total_cost_for_session(session_id), to: Aggregations
  defdelegate total_tokens_for_session(session_id), to: Aggregations
  defdelegate mark_processing(message_id), to: StatusManager
  defdelegate mark_delivered(message_id), to: StatusManager
  defdelegate mark_failed(message_id, reason), to: StatusManager

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp message_defaults(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs
    |> Map.put_new(:uuid, Ecto.UUID.generate())
    |> Map.put_new(:inserted_at, now)
    |> Map.put_new(:updated_at, now)
  end

  defp broadcast_and_return({:ok, message}) do
    if message.channel_id do
      EyeInTheSky.Events.channel_message(message.channel_id, message)
    else
      EyeInTheSky.Events.session_new_message(message.session_id, message)
    end

    {:ok, message}
  end

  defp broadcast_and_return(error), do: error

  # Increments the session's cached token/cost totals when a message carries
  # usage metadata. Silently skips when session_id or usage fields are absent.
  defp maybe_increment_session_cache(%Message{session_id: nil}), do: :ok

  defp maybe_increment_session_cache(%Message{session_id: session_id, metadata: metadata})
       when is_map(metadata) do
    usage = Map.get(metadata, "usage") || Map.get(metadata, :usage) || %{}
    input = get_int(usage, "input_tokens") + get_int(usage, :input_tokens)
    output = get_int(usage, "output_tokens") + get_int(usage, :output_tokens)
    cost = get_float(metadata, "total_cost_usd") + get_float(metadata, :total_cost_usd)
    Sessions.increment_usage_cache(session_id, input + output, cost)
  end

  defp maybe_increment_session_cache(_message), do: :ok

  defp get_int(map, key) when is_map(map) do
    case Map.get(map, key) do
      v when is_integer(v) -> v
      v when is_binary(v) ->
        case Integer.parse(v) do
          {n, _} -> n
          :error -> 0
        end
      _ -> 0
    end
  end

  defp get_float(map, key) when is_map(map) do
    case Map.get(map, key) do
      v when is_float(v) -> v
      v when is_integer(v) -> v * 1.0
      v when is_binary(v) ->
        case Float.parse(v) do
          {f, _} -> f
          :error -> 0.0
        end
      _ -> 0.0
    end
  end
end
