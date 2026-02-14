defmodule EyeInTheSkyWeb.Messages.JsonlStorage do
  @moduledoc """
  Handles reading and writing messages from/to JSONL files.
  JSONL format: Each line is a complete JSON message object.

  Storage location: ~/.claude/projects/{projectId}/{sessionId}.jsonl
  """

  require Logger
  alias EyeInTheSkyWeb.Messages.Message

  @doc """
  Gets the path to a session's JSONL file.
  """
  def get_session_file_path(project_id, session_id) do
    claude_dir = Path.expand("~/.claude")
    Path.join([claude_dir, "projects", project_id, "#{session_id}.jsonl"])
  end

  @doc """
  Reads all messages from a session's JSONL file.
  Returns a list of Message structs in chronological order.
  """
  def read_session_messages(project_id, session_id) do
    file_path = get_session_file_path(project_id, session_id)

    case File.exists?(file_path) do
      true ->
        file_path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Stream.map(&parse_jsonl_line/1)
        |> Stream.filter(& &1)
        |> Enum.sort_by(fn msg -> msg.inserted_at || DateTime.utc_now() end)

      false ->
        Logger.debug("Session file not found: #{file_path}")
        []
    end
  end

  @doc """
  Appends a message to a session's JSONL file.
  """
  def append_message(project_id, session_id, message_data) do
    file_path = get_session_file_path(project_id, session_id)

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(file_path))

    # Convert message to JSON line
    json_line = Jason.encode!(message_data) <> "\n"

    # Append to file
    case File.write(file_path, json_line, [:append]) do
      :ok ->
        Logger.debug("Appended message to session file: #{file_path}")
        {:ok, message_data}

      {:error, reason} ->
        Logger.error("Failed to append message to #{file_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Parses a single JSONL line into a Message struct.
  defp parse_jsonl_line(line) do
    case Jason.decode(line) do
      {:ok, data} ->
        # Convert JSON data to Message struct
        convert_to_message(data)

      {:error, reason} ->
        Logger.warn("Failed to parse JSONL line: #{inspect(reason)}")
        nil
    end
  end

  # Converts a JSON object to a Message struct.
  defp convert_to_message(data) do
    # Parse timestamps if they're strings
    inserted_at = parse_timestamp(data["inserted_at"] || data["timestamp"])
    updated_at = parse_timestamp(data["updated_at"])

    %Message{
      id: data["id"] || Ecto.UUID.generate(),
      project_id: data["project_id"],
      session_id: data["session_id"],
      channel_id: data["channel_id"],
      parent_message_id: data["parent_message_id"],
      sender_role: data["sender_role"] || "user",
      recipient_role: data["recipient_role"],
      provider: data["provider"],
      provider_session_id: data["provider_session_id"],
      direction: data["direction"] || "inbound",
      body: data["body"] || data["content"] || "",
      status: data["status"] || "sent",
      metadata: data["metadata"] || %{},
      thread_reply_count: data["thread_reply_count"] || 0,
      last_thread_reply_at: parse_timestamp(data["last_thread_reply_at"]),
      inserted_at: inserted_at,
      updated_at: updated_at || inserted_at
    }
  end

  # Parses a timestamp string to DateTime.
  # Handles ISO 8601 format and Unix timestamps.
  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> parse_unix_timestamp(timestamp)
    end
  end

  defp parse_timestamp(timestamp) when is_integer(timestamp) do
    parse_unix_timestamp(timestamp)
  end

  defp parse_timestamp(_), do: nil

  defp parse_unix_timestamp(timestamp) when is_binary(timestamp) do
    case Integer.parse(timestamp) do
      {seconds, ""} -> DateTime.from_unix!(seconds)
      _ -> nil
    end
  end

  defp parse_unix_timestamp(seconds) when is_integer(seconds) do
    DateTime.from_unix!(seconds)
  end

  defp parse_unix_timestamp(_), do: nil

  @doc """
  Writes all messages for a session to JSONL file.
  Useful for bulk initialization or migration.
  """
  def write_session_messages(project_id, session_id, messages) do
    file_path = get_session_file_path(project_id, session_id)

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(file_path))

    # Convert messages to JSONL format
    jsonl_content =
      messages
      |> Enum.map(&message_to_json_data/1)
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    case File.write(file_path, jsonl_content <> "\n") do
      :ok ->
        Logger.info("Wrote #{Enum.count(messages)} messages to #{file_path}")
        {:ok, file_path}

      {:error, reason} ->
        Logger.error("Failed to write messages to #{file_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Converts a Message struct to a JSON-serializable map.
  defp message_to_json_data(%Message{} = message) do
    %{
      "id" => message.id,
      "project_id" => message.project_id,
      "session_id" => message.session_id,
      "channel_id" => message.channel_id,
      "parent_message_id" => message.parent_message_id,
      "sender_role" => message.sender_role,
      "recipient_role" => message.recipient_role,
      "provider" => message.provider,
      "provider_session_id" => message.provider_session_id,
      "direction" => message.direction,
      "body" => message.body,
      "status" => message.status,
      "metadata" => message.metadata,
      "thread_reply_count" => message.thread_reply_count,
      "last_thread_reply_at" =>
        if(message.last_thread_reply_at, do: DateTime.to_iso8601(message.last_thread_reply_at)),
      "inserted_at" => if(message.inserted_at, do: DateTime.to_iso8601(message.inserted_at)),
      "updated_at" => if(message.updated_at, do: DateTime.to_iso8601(message.updated_at))
    }
    |> Enum.reject(fn {_k, v} -> v == nil end)
    |> Enum.into(%{})
  end

  defp message_to_json_data(data) when is_map(data) do
    data
  end
end
