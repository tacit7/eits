defmodule EyeInTheSky.Claude.SessionImporter do
  @moduledoc """
  Imports messages from JSONL session files into the database.

  Handles reading raw messages from the session file via `SessionReader`,
  deduplicating against existing DB records, and persisting new ones.
  """

  alias EyeInTheSky.Messages
  alias EyeInTheSky.Claude.SessionReader

  require Logger

  @doc """
  Reads new messages from the session file and imports them into the DB.

  Returns `{:ok, count}` on success, `{:error, reason}` if the file can't be read.
  """
  @spec sync(String.t(), String.t(), integer()) :: {:ok, integer()} | {:error, term()}
  def sync(session_uuid, project_path, session_id) do
    last_uuid = Messages.get_last_source_uuid(session_id)

    with {:ok, raw_messages} <-
           SessionReader.read_messages_after_uuid(session_uuid, project_path, last_uuid) do
      {:ok, import_messages(raw_messages, session_id)}
    end
  end

  @doc """
  Formats and imports a list of raw session messages into the DB for the given session.

  Returns the count of successfully imported messages.
  """
  @spec import_messages(list(), integer()) :: integer()
  def import_messages(raw_messages, session_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    raw_messages
    |> SessionReader.format_messages()
    |> Enum.filter(& &1.uuid)
    |> Enum.count(&import_message(&1, session_id, now))
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp import_message(msg, session_id, now) do
    {sender_role, recipient_role, direction} = message_roles(msg.role)
    inserted_at = parse_timestamp(msg.timestamp, now)

    metadata =
      cond do
        msg[:stream_type] == "tool_result" -> %{"stream_type" => "tool_result"}
        msg.usage -> %{"usage" => msg.usage}
        true -> nil
      end

    case Messages.find_unlinked_message(session_id, sender_role, msg.content) do
      {:ok, existing} ->
        update_attrs = %{source_uuid: msg.uuid, updated_at: now}

        update_attrs =
          if metadata, do: Map.put(update_attrs, :metadata, metadata), else: update_attrs

        Messages.update_message(existing, update_attrs)
        true

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
               provider: "claude",
               metadata: metadata,
               inserted_at: inserted_at,
               updated_at: now
             }) do
          {:ok, _message} ->
            true

          {:error, reason} ->
            Logger.debug("Skipping imported message source_uuid=#{msg.uuid}: #{inspect(reason)}")
            false
        end
    end
  rescue
    e in Postgrex.Error ->
      Logger.warning("SessionImporter: Postgrex error importing source_uuid=#{msg.uuid}: #{inspect(e)}")
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
end
