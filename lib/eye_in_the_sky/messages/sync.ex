defmodule EyeInTheSky.Messages.Sync do
  @moduledoc """
  Handles syncing messages between JSONL files and the database.

  Two storage backends are supported:
  - JSONL: used when `project_id` is a binary string (reads from
    `~/.claude/projects/{project_id}/{session_id}.jsonl`, falls back to DB if empty).
  - Database: used when `project_id` is nil or any non-binary value.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Messages.JsonlStorage
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.QueryHelpers
  require Logger

  @spec list_messages_for_session(integer()) :: [Message.t()]
  def list_messages_for_session(session_id), do: list_messages_for_session(session_id, nil)

  @doc """
  Returns messages for a session.

  Two storage backends are supported:
  - JSONL: used when `project_id` is a binary string (reads from
    `~/.claude/projects/{project_id}/{session_id}.jsonl`, falls back to DB if empty).
  - Database: used when `project_id` is nil or any non-binary value.
  """
  @spec list_messages_for_session(integer(), binary() | nil) :: [Message.t()]
  def list_messages_for_session(session_id, project_id) do
    load_messages(session_id, project_id)
  end

  # Private: Load messages from JSONL if project_id is a binary string, otherwise from DB
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

  # Private: Load messages from database
  defp list_messages_for_session_db(session_id) do
    QueryHelpers.for_session_direct(Message, session_id, order_by: [asc: :inserted_at])
  end
end
