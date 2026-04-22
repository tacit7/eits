defmodule EyeInTheSky.Messages.BulkImporter do
  @moduledoc """
  Shared import logic for session messages from any provider.

  Handles deduplication against existing DB records and persisting new ones.
  Provider-specific importers (Claude, Codex) prepare their messages and
  delegate here.

  Uses Repo.transaction and Repo.insert_all for atomic, efficient batch operations.
  """

  alias EyeInTheSky.Messages
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Repo

  require Logger

  @doc """
  Imports a list of pre-parsed messages into the DB for the given session.

  Options:
    - `:provider` - (required) provider string, e.g. "claude" or "codex"
    - `:metadata_fn` - optional 1-arity function returning a metadata map or nil for a message

  Returns the count of successfully imported messages.
  """
  @spec import_messages(list(map()), integer(), keyword()) :: integer()
  def import_messages(messages, session_id, opts) do
    provider = Keyword.fetch!(opts, :provider)
    metadata_fn = Keyword.get(opts, :metadata_fn, fn _msg -> nil end)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    messages_with_uuid = Enum.filter(messages, & &1.uuid)
    uuids = Enum.map(messages_with_uuid, & &1.uuid)
    existing = Messages.existing_source_uuids(session_id, uuids)

    context = %{
      session_id: session_id,
      now: now,
      provider: provider,
      metadata_fn: metadata_fn,
      existing_source_uuids: existing
    }

    # Separate messages into actions: updates (link existing), inserts (create new), skips
    {updates, inserts, skip_count} =
      Enum.reduce(messages_with_uuid, {[], [], 0}, fn msg, {upd_acc, ins_acc, skip_count} ->
        process_message(msg, context, upd_acc, ins_acc, skip_count)
      end)

    # Execute in transaction
    result =
      Repo.transaction(fn ->
        # Batch insert new messages with conflict resolution
        insert_count =
          if Enum.empty?(inserts) do
            0
          else
            {count, _} =
              Repo.insert_all(Message, inserts,
                on_conflict: :nothing,
                conflict_target: :source_uuid
              )

            count
          end

        # Per-row updates (usually fewer than inserts)
        update_count =
          Enum.count(updates, fn {existing, update_attrs} ->
            case Messages.update_message(existing, update_attrs) do
              {:ok, _} ->
                true

              {:error, reason} ->
                Logger.debug(
                  "BulkImporter: failed to link message #{existing.id}: #{inspect(reason)}"
                )

                false
            end
          end)

        insert_count + update_count
      end)

    case result do
      {:ok, count} -> count + skip_count
      {:error, reason} ->
        Logger.warning("BulkImporter: transaction failed: #{inspect(reason)}")
        0
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp process_message(msg, context, upd_acc, ins_acc, skip_count) do
    %{
      session_id: session_id,
      now: now,
      provider: provider,
      metadata_fn: metadata_fn,
      existing_source_uuids: existing_source_uuids
    } = context

    cond do
      # Fast-path: if this source_uuid is already in the DB, skip the expensive body scan.
      MapSet.member?(existing_source_uuids, msg.uuid) ->
        {upd_acc, ins_acc, skip_count + 1}

      # Avoid double-rendering DMs. When a DM arrives, DMDelivery persists it
      # as sender_role: "agent" (inbound) and forwards it to the local CLI as
      # a user prompt; the session file then replays that prompt as
      # role: "user". The find_unlinked_message lookup below only matches on
      # sender_role, so the inbound "agent" row is invisible to it and a
      # second outbound/user row gets created with the same body, making the
      # DM render twice in the chat (once received, once "sent"). Skip the
      # import when a recent inbound DM with the same body already exists.
      msg.role == "user" and dm_already_recorded?(session_id, msg.content) ->
        {upd_acc, ins_acc, skip_count + 1}

      true ->
        {sender_role, recipient_role, direction} = message_roles(msg.role)
        inserted_at = parse_timestamp(msg.timestamp, now)
        metadata = metadata_fn.(msg)

        case Messages.find_unlinked_message(session_id, sender_role, msg.content) do
          {:ok, existing} ->
            # Message exists but has no source_uuid; link it
            update_attrs = %{source_uuid: msg.uuid, updated_at: now}

            update_attrs =
              if metadata, do: Map.put(update_attrs, :metadata, metadata), else: update_attrs

            {[{existing, update_attrs} | upd_acc], ins_acc, skip_count}

          :not_found ->
            # New message; prepare for batch insert
            new_message = %{
              uuid: Ecto.UUID.generate(),
              source_uuid: msg.uuid,
              session_id: session_id,
              sender_role: sender_role,
              recipient_role: recipient_role,
              direction: direction,
              body: msg.content,
              status: "delivered",
              provider: provider,
              metadata: metadata,
              inserted_at: inserted_at,
              updated_at: now
            }

            {upd_acc, [new_message | ins_acc], skip_count}
        end
    end
  rescue
    e in Postgrex.Error ->
      Logger.warning("BulkImporter: Postgrex error processing message: #{inspect(e)}")
      {upd_acc, ins_acc, skip_count + 1}
  end

  defp dm_already_recorded?(session_id, body) do
    case Messages.find_recent_dm(session_id, body, seconds: 86_400) do
      nil -> false
      _msg -> true
    end
  end

  defp message_roles("user"), do: {"user", "agent", "outbound"}
  defp message_roles(_role), do: {"agent", "user", "inbound"}

  defp parse_timestamp(timestamp, fallback) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> fallback
    end
  end

  defp parse_timestamp(_timestamp, fallback), do: fallback
end
