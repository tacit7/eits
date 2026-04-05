defmodule EyeInTheSky.Codex.SessionImporter do
  @moduledoc """
  Imports messages from Codex session JSONL files into the database.

  Mirrors EyeInTheSky.Claude.SessionImporter but uses Codex.SessionReader
  to parse the different file format Codex uses.
  """

  alias EyeInTheSky.Codex.SessionReader
  alias EyeInTheSky.Messages

  require Logger

  @doc """
  Reads all messages from the Codex session file and imports any that aren't
  already in the DB (matched by source_uuid).

  Returns {:ok, count} on success, {:error, reason} on file read failure.
  """
  @spec sync(String.t(), integer()) :: {:ok, integer()} | {:error, term()}
  def sync(thread_id, session_id) do
    with {:ok, messages} <- SessionReader.read_messages(thread_id) do
      {:ok, import_messages(messages, session_id)}
    end
  end

  @doc """
  Imports a list of already-parsed messages into the DB for the given session.
  Skips messages already present (matched by source_uuid).

  Returns the count of successfully imported messages.
  """
  @spec import_messages(list(map()), integer()) :: integer()
  def import_messages(messages, session_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    messages
    |> Enum.filter(& &1.uuid)
    |> Enum.count(&import_message(&1, session_id, now))
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp import_message(msg, session_id, now) do
    {sender_role, recipient_role, direction} = message_roles(msg.role)
    inserted_at = parse_timestamp(msg.timestamp, now)

    case Messages.find_unlinked_message(session_id, sender_role, msg.content) do
      {:ok, existing} ->
        Messages.update_message(existing, %{source_uuid: msg.uuid, updated_at: now})
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
               provider: "codex",
               metadata: nil,
               inserted_at: inserted_at,
               updated_at: now
             }) do
          {:ok, _} ->
            true

          {:error, reason} ->
            Logger.debug(
              "Skipping imported Codex message source_uuid=#{msg.uuid}: #{inspect(reason)}"
            )

            false
        end
    end
  end

  defp message_roles("user"), do: {"user", "agent", "outbound"}
  defp message_roles(_), do: {"agent", "user", "inbound"}

  defp parse_timestamp(timestamp, fallback) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> fallback
    end
  end

  defp parse_timestamp(_timestamp, fallback), do: fallback
end
