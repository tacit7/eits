defmodule EyeInTheSky.Messages.Deduplicator do
  @moduledoc """
  Deduplication and recent-message lookup helpers for the Messages context.

  Extracted from `EyeInTheSky.Messages` to keep the main context module focused
  on CRUD and lifecycle operations. `Messages` delegates deduplication and
  metadata-enrichment calls here; callers should continue to use the `Messages`
  public API.
  """

  import Ecto.Query, warn: false

  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Repo

  @doc """
  Removes duplicate messages by `source_uuid`, keeping the first occurrence.

  Messages without a `source_uuid` are always kept.
  """
  @spec deduplicate_by_source_uuid([Message.t()]) :: [Message.t()]
  def deduplicate_by_source_uuid(messages) do
    messages
    |> Enum.reduce({[], MapSet.new()}, &dedup_step/2)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc """
  Finds the most recent message in the session matching the given body within the last minute.

  Options:
    * `:sender_role` - filter by sender role (default `"agent"`)
    * `:require_nil_source_uuid` - when `true`, only matches messages where
      `source_uuid` is nil (default `false`)

  Returns the matching `%Message{}` or `nil`.
  """
  @spec find_recent_message(integer(), String.t(), keyword()) :: Message.t() | nil
  def find_recent_message(session_id, body, opts \\ []) do
    sender_role = Keyword.get(opts, :sender_role, "agent")
    require_nil_source_uuid = Keyword.get(opts, :require_nil_source_uuid, false)
    max_age_seconds = Keyword.get(opts, :max_age_seconds, 60)

    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-max_age_seconds, :second)
      |> DateTime.truncate(:second)

    Message
    |> where(
      [m],
      m.session_id == ^session_id and
        m.sender_role == ^sender_role and
        m.body == ^body and
        m.inserted_at >= ^cutoff
    )
    |> then(fn query ->
      if require_nil_source_uuid, do: where(query, [m], is_nil(m.source_uuid)), else: query
    end)
    |> order_by([m], desc: m.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Finds an existing message by `source_uuid` or inserts a new one.

  Routing logic:
    - `source_uuid` already stored → enrich metadata on the existing record
    - `source_uuid` not yet stored → insert

  Returns `{:ok, message}` on success, or `{:error, :source_uuid_required}` when
  `source_uuid` is absent or not a binary.
  """
  @spec find_or_create(map(), map()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()} | {:error, :source_uuid_required}
  def find_or_create(%{source_uuid: uuid} = attrs, metadata) when is_binary(uuid) do
    case Repo.get_by(Message, source_uuid: uuid) do
      nil -> do_insert(attrs)
      existing -> enrich_metadata_if_present(existing, metadata)
    end
  end

  def find_or_create(_attrs, _metadata), do: {:error, :source_uuid_required}

  @doc """
  Enriches an existing message with metadata if metadata is provided and non-empty.

  When `metadata` is `nil` or `%{}`, returns `{:ok, message}` unchanged.
  Otherwise delegates to `EyeInTheSky.Messages.update_message/2`.
  """
  @spec enrich_metadata_if_present(Message.t(), map()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def enrich_metadata_if_present(message, metadata) do
    if metadata && metadata != %{} do
      EyeInTheSky.Messages.update_message(message, %{metadata: metadata})
    else
      {:ok, message}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_insert(attrs) do
    cid = Map.get(attrs, :channel_id)

    if cid,
      do: EyeInTheSky.Messages.create_channel_message(attrs),
      else: EyeInTheSky.Messages.create_message(attrs)
  end

  defp dedup_step(msg, {acc, seen_uuids}) do
    if msg.source_uuid && MapSet.member?(seen_uuids, msg.source_uuid) do
      {acc, seen_uuids}
    else
      new_seen = if msg.source_uuid, do: MapSet.put(seen_uuids, msg.source_uuid), else: seen_uuids
      {[msg | acc], new_seen}
    end
  end
end
