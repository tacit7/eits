defmodule EyeInTheSky.Gemini.SessionImporter do
  @moduledoc """
  Imports messages from Gemini CLI session JSONL files into the database.

  Thin adapter over `EyeInTheSky.Messages.BulkImporter` — handles
  Gemini-specific file reading via `Gemini.SessionReader` and delegates
  shared import / dedup logic.
  """

  alias EyeInTheSky.Gemini.SessionReader
  alias EyeInTheSky.Messages
  alias EyeInTheSky.Messages.BulkImporter

  @doc """
  Read messages from the Gemini session file that came after the last
  imported message and persist any not already in the DB (matched by
  source_uuid).

  Returns `{:ok, %{inserted, updated, skipped}}` on success.
  """
  @spec sync(String.t(), String.t() | nil, integer()) ::
          {:ok, %{inserted: integer(), updated: integer(), skipped: integer()}}
          | {:error, term()}
  def sync(session_uuid, project_path, session_id) do
    last_uuid = Messages.get_last_source_uuid(session_id)

    with {:ok, messages} <-
           SessionReader.read_messages_after_uuid(session_uuid, project_path, last_uuid) do
      {:ok, import_messages(messages, session_id)}
    end
  end

  @doc """
  Persist a pre-parsed list of messages.

  Skips rows whose `source_uuid` already exists. Returns the per-row
  counts produced by `BulkImporter`.
  """
  @spec import_messages(list(map()), integer()) ::
          %{inserted: integer(), updated: integer(), skipped: integer()}
  def import_messages(messages, session_id) do
    BulkImporter.import_messages(messages, session_id,
      provider: "gemini",
      importing_from_file?: true
    )
  end
end
