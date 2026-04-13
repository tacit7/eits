defmodule EyeInTheSky.Codex.SessionImporter do
  @moduledoc """
  Imports messages from Codex session JSONL files into the database.

  Thin adapter over `EyeInTheSky.Messages.BulkImporter` — handles Codex-specific
  file reading via `Codex.SessionReader` and delegates shared import logic.
  """

  alias EyeInTheSky.Codex.SessionReader
  alias EyeInTheSky.Messages.BulkImporter

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
    BulkImporter.import_messages(messages, session_id, provider: "codex")
  end
end
