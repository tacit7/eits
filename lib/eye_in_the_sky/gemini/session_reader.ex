defmodule EyeInTheSky.Gemini.SessionReader do
  @moduledoc """
  Reads Gemini CLI session files from ~/.gemini/tmp/<project>/chats/ and
  extracts conversation messages.

  Gemini CLI persists each chat session as a JSONL file:

      ~/.gemini/tmp/<project_dir>/chats/session-<timestamp>-<sessionId-prefix>.jsonl

  The first line is a manifest:

      {"sessionId":"<uuid>","projectHash":"<sha256>","startTime":"...",
       "lastUpdated":"...","kind":"main","summary":"..."}

  Each subsequent line is a turn:

    * User turn:
        {"id":"<uuid>","timestamp":"...","type":"user",
         "content":[{"text":"<body>"}]}

    * Gemini turn:
        {"id":"<uuid>","timestamp":"...","type":"gemini",
         "content":"<body>","thoughts":[...],"tokens":{...},
         "model":"...","toolCalls":[...]}

  We surface user + gemini text turns to the SessionImporter. Tool calls
  are dropped for now — they show up live via the StreamHandler and don't
  need to be re-derived from the file.

  `<project_dir>` may be either a SHA-256 hex of the absolute project path
  or a friendly basename (older Gemini CLI versions). We try both: hash
  first, then a basename-of(project_path) fallback. The match is
  confirmed by reading the manifest's `sessionId`.
  """

  require Logger

  @doc """
  Locate the Gemini session JSONL for a given session UUID.

  The optional `project_path` narrows the search to one subdir. If omitted
  or no match found there, the full tmp tree is scanned. Returns the .jsonl
  variant when both .json and .jsonl exist (the .jsonl is the canonical
  append-log; the .json is a static snapshot Gemini also writes).
  """
  @spec find_session_file(String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, :not_found}
  def find_session_file(nil, _), do: {:error, :not_found}

  def find_session_file(session_uuid, project_path) when is_binary(session_uuid) do
    home = System.get_env("HOME")
    base = Path.join([home, ".gemini", "tmp"])

    # Candidate chat directories — ordered by likelihood:
    #   1. SHA-256(project_path)/chats — current Gemini CLI convention
    #   2. basename(project_path)/chats — older / friendly-name convention
    #   3. every */chats — last-resort full scan
    candidate_dirs = candidate_chat_dirs(base, project_path)

    candidate_dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "session-*-*.jsonl")))
    |> Enum.uniq()
    |> Enum.find(&file_session_id_matches?(&1, session_uuid))
    |> case do
      nil -> {:error, :not_found}
      path -> {:ok, path}
    end
  end

  @doc """
  Read all conversation messages from the session JSONL.

  Returns `{:ok, [%{uuid, role, content, timestamp, usage, stream_type}]}`
  suitable for feeding `EyeInTheSky.Messages.BulkImporter.import_messages/3`.
  """
  @spec read_messages(String.t(), String.t() | nil) ::
          {:ok, list(map())} | {:error, term()}
  def read_messages(session_uuid, project_path \\ nil) do
    with {:ok, path} <- find_session_file(session_uuid, project_path),
         {:ok, content} <- File.read(path) do
      messages =
        content
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&extract_message/1)

      {:ok, messages}
    end
  end

  @doc """
  Same as `read_messages/2` but drops every message whose `uuid` is on or
  before `after_uuid` in the file. Used for incremental sync.

  If `after_uuid` is `nil` or not found in the file, returns all messages.
  """
  @spec read_messages_after_uuid(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, list(map())} | {:error, term()}
  def read_messages_after_uuid(session_uuid, project_path, after_uuid) do
    with {:ok, messages} <- read_messages(session_uuid, project_path) do
      {:ok, drop_messages_before(messages, after_uuid)}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp candidate_chat_dirs(base, project_path) do
    explicit =
      cond do
        is_binary(project_path) and project_path != "" ->
          hash = :crypto.hash(:sha256, project_path) |> Base.encode16(case: :lower)
          basename = Path.basename(project_path)

          [
            Path.join([base, hash, "chats"]),
            Path.join([base, basename, "chats"])
          ]

        true ->
          []
      end

    fallback = Path.wildcard(Path.join([base, "*", "chats"]))

    (explicit ++ fallback) |> Enum.uniq()
  end

  defp file_session_id_matches?(path, session_uuid) do
    case File.stream!(path, [], :line) |> Enum.take(1) do
      [manifest] ->
        case Jason.decode(manifest) do
          {:ok, %{"sessionId" => ^session_uuid}} -> true
          _ -> false
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp drop_messages_before(messages, nil), do: messages

  defp drop_messages_before(messages, after_uuid) do
    case Enum.find_index(messages, fn msg -> msg.uuid == after_uuid end) do
      nil -> messages
      idx -> Enum.drop(messages, idx + 1)
    end
  end

  defp extract_message(line) do
    case Jason.decode(line) do
      {:ok, decoded} -> extract_decoded(decoded)
      _ -> []
    end
  end

  # Skip the first-line manifest.
  defp extract_decoded(%{"sessionId" => _, "projectHash" => _}), do: []

  # User turn: content is a list of content blocks, each with "text".
  defp extract_decoded(%{
         "id" => id,
         "type" => "user",
         "content" => content,
         "timestamp" => ts
       }) do
    text = extract_user_text(content)

    if text == "" do
      []
    else
      [
        %{
          uuid: id,
          role: "user",
          content: text,
          timestamp: ts,
          usage: nil,
          stream_type: nil
        }
      ]
    end
  end

  # Gemini turn: content is a string. Empty content turns (tool-call-only
  # turns where the model produced no prose) are dropped so the imported
  # transcript matches what the UI rendered.
  defp extract_decoded(%{
         "id" => id,
         "type" => "gemini",
         "content" => content,
         "timestamp" => ts
       } = msg)
       when is_binary(content) and content != "" do
    [
      %{
        uuid: id,
        role: "assistant",
        content: content,
        timestamp: ts,
        usage: Map.get(msg, "tokens"),
        model: Map.get(msg, "model"),
        stream_type: nil
      }
    ]
  end

  defp extract_decoded(_), do: []

  defp extract_user_text(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"text" => t} when is_binary(t) -> t
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp extract_user_text(text) when is_binary(text), do: text
  defp extract_user_text(_), do: ""
end
