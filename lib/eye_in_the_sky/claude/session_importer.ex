defmodule EyeInTheSky.Claude.SessionImporter do
  @moduledoc """
  Imports messages from JSONL session files into the database.

  Handles reading raw messages from the session file via `SessionReader`,
  deduplicating against existing DB records, and persisting new ones.
  Delegates shared import logic to `EyeInTheSky.Messages.BulkImporter`.
  """

  alias EyeInTheSky.Claude.SessionReader
  alias EyeInTheSky.Messages
  alias EyeInTheSky.Messages.BulkImporter

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
    raw_messages
    |> SessionReader.format_messages()
    |> BulkImporter.import_messages(session_id,
      provider: "claude",
      metadata_fn: &extract_metadata/1,
      importing_from_file?: true
    )
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp extract_metadata(msg) do
    cond do
      msg[:stream_type] == "tool_result" -> %{"stream_type" => "tool_result"}
      msg.usage -> %{"usage" => msg.usage}
      true -> nil
    end
  end
end
