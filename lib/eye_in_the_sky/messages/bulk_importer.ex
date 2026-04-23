defmodule EyeInTheSky.Messages.BulkImporter do
  @moduledoc """
  Shared import logic for session messages from any provider.

  Handles deduplication against existing DB records and persisting new ones.
  Provider-specific importers (Claude, Codex) prepare their messages and
  delegate here.
  """

  alias EyeInTheSky.Events
  alias EyeInTheSky.Messages

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

    context = %{session_id: session_id, now: now, provider: provider, metadata_fn: metadata_fn}

    messages
    |> Enum.filter(& &1.uuid)
    |> Enum.count(&import_message(&1, context))
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp import_message(msg, context) do
    %{session_id: session_id, now: now, provider: provider, metadata_fn: metadata_fn} = context
    {sender_role, recipient_role, direction} = message_roles(msg.role)
    inserted_at = parse_timestamp(msg.timestamp, now)
    metadata = metadata_fn.(msg)

    case Messages.find_unlinked_message(session_id, sender_role, msg.content) do
      {:ok, existing} ->
        update_attrs = %{source_uuid: msg.uuid, updated_at: now}

        update_attrs =
          if metadata, do: Map.put(update_attrs, :metadata, metadata), else: update_attrs

        case Messages.update_message(existing, update_attrs) do
          {:ok, linked} ->
            broadcast_new_message(session_id, linked)
            true

          {:error, reason} ->
            Logger.debug(
              "BulkImporter: failed to link #{provider} message #{existing.id}: #{inspect(reason)}"
            )

            false
        end

      :not_found ->
        case Messages.create_message(%{
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
             }) do
          {:ok, created} ->
            broadcast_new_message(session_id, created)
            true

          {:error, reason} ->
            Logger.debug(
              "BulkImporter: skipping #{provider} message source_uuid=#{msg.uuid}: #{inspect(reason)}"
            )

            false
        end
    end
  rescue
    e in Postgrex.Error ->
      Logger.warning(
        "BulkImporter: Postgrex error importing source_uuid=#{msg.uuid}: #{inspect(e)}"
      )

      false
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

  # Broadcast newly inserted/linked messages so DmLive (and any other
  # session subscriber) sees real-time updates without a page refresh.
  # Wrapped in try/rescue so a broken topic doesn't abort the import loop.
  defp broadcast_new_message(session_id, message) do
    Events.session_new_message(session_id, message)
  rescue
    e ->
      Logger.error(
        "BulkImporter: broadcast failed for session=#{session_id} msg=#{message.id}: #{Exception.message(e)}"
      )
  end
end
