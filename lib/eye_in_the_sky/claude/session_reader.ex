defmodule EyeInTheSky.Claude.SessionReader do
  @moduledoc """
  Reads Claude Code session files from ~/.claude/projects/ and extracts conversation messages.
  """

  alias EyeInTheSky.Claude.SessionFileLocator
  alias EyeInTheSky.Claude.MessageFormatter

  @doc """
  Discovers all Claude Code sessions by scanning ~/.claude/projects/ directory.
  Returns a list of session maps with basic metadata.
  """
  def discover_all_sessions do
    home = System.get_env("HOME")
    projects_dir = Path.join([home, ".claude", "projects"])

    case File.ls(projects_dir) do
      {:ok, project_dirs} ->
        project_dirs
        |> Enum.flat_map(fn project_dir ->
          project_path = Path.join(projects_dir, project_dir)
          discover_sessions_in_project(project_path, project_dir)
        end)

      {:error, _} ->
        []
    end
  end

  defp discover_sessions_in_project(project_path, escaped_project_name) do
    case File.ls(project_path) do
      {:ok, files} ->
        for filename <- files, String.ends_with?(filename, ".jsonl") do
          session_id = String.replace_suffix(filename, ".jsonl", "")
          file_path = Path.join(project_path, filename)
          file_stat = File.stat!(file_path)

          %{
            session_id: session_id,
            # escaped_path is the exact directory name on disk — use this when
            # constructing file paths to avoid ambiguity.
            escaped_path: escaped_project_name,
            # project_path is a best-effort unescaping and is LOSSY: paths that
            # contain hyphens (e.g. /Users/foo/my-app) cannot be distinguished
            # from path separators once escaped. Use escaped_path for file I/O.
            project_path: unescape_project_path(escaped_project_name),
            last_modified: file_stat.mtime,
            file_size: file_stat.size,
            discovered: true
          }
        end

      {:error, _} ->
        []
    end
  end

  # LOSSY: /Users/foo/my-app and /Users/foo/my/app both escape to -Users-foo-my-app.
  # Unescaping is fundamentally ambiguous — hyphens in directory names are
  # indistinguishable from path separators. Use escaped_path from discover_all_sessions
  # for any file I/O; treat project_path as a human-readable hint only.
  defp unescape_project_path(escaped_path) do
    escaped_path
    |> String.replace(~r/^-/, "/")
    |> String.replace("-", "/")
  end

  @doc """
  Reads the last N messages from a Claude session file.

  ## Parameters
  - session_id: The Claude session UUID
  - project_path: The git worktree path (e.g., "/Users/user/projects/myapp")
  - limit: Number of recent messages to return (default: 10)

  ## Returns
  List of message maps with :role, :content, :timestamp
  """
  def read_recent_messages(session_id, project_path, limit \\ 10) do
    with_session_file(session_id, project_path, fn lines ->
      messages =
        lines
        |> Enum.map(&parse_line/1)
        |> Enum.filter(&conversation_message?/1)
        |> Enum.take(-limit)

      {:ok, messages}
    end)
  end

  @doc """
  Finds the Claude session JSONL file path.
  Claude stores sessions in: ~/.claude/projects/<escaped-project-path>/<session-id>.jsonl
  """
  def find_session_file(session_id, project_path) do
    SessionFileLocator.locate(session_id, project_path)
  end

  @doc """
  Escapes project path for Claude's directory naming convention.
  Delegates to SessionFileLocator.escape_project_path/1.
  """
  defdelegate escape_project_path(path), to: SessionFileLocator

  @doc """
  Reads messages from a session file that come after the given uuid.
  If after_uuid is nil, reads all messages. Used for incremental sync.
  """
  def read_messages_after_uuid(session_id, project_path, after_uuid) do
    with_session_file(session_id, project_path, fn lines ->
      all_messages =
        lines
        |> Enum.map(&parse_line/1)
        |> Enum.filter(&conversation_message?/1)

      result =
        if after_uuid, do: drop_messages_before(all_messages, after_uuid), else: all_messages

      {:ok, result}
    end)
  end

  @doc """
  Parses a Claude session JSONL file and extracts conversation messages.
  Returns the last N messages in chronological order.
  """
  def parse_session_file(file_path, limit) do
    case read_all_lines(file_path) do
      {:ok, lines} ->
        messages =
          lines
          |> Enum.map(&parse_line/1)
          |> Enum.filter(&conversation_message?/1)
          |> Enum.take(-limit)

        {:ok, messages}

      {:error, _} = err ->
        err
    end
  end

  defp with_session_file(session_id, project_path, fun) do
    case find_session_file(session_id, project_path) do
      {:error, _} = error ->
        error

      {:ok, file_path} ->
        case read_all_lines(file_path) do
          {:error, _} = error -> error
          {:ok, lines} -> fun.(lines)
        end
    end
  end

  defp read_all_lines(file_path) do
    case File.read(file_path) do
      {:ok, content} -> {:ok, String.split(content, "\n", trim: true)}
      {:error, _} = err -> err
    end
  end

  defp drop_messages_before(all_messages, after_uuid) do
    case Enum.find_index(all_messages, fn msg -> msg["uuid"] == after_uuid end) do
      nil -> all_messages
      idx -> Enum.drop(all_messages, idx + 1)
    end
  end

  defp parse_line(line) do
    case Jason.decode(line) do
      {:ok, json} -> json
      {:error, _} -> nil
    end
  end

  defp conversation_message?(nil), do: false
  defp conversation_message?(%{"type" => type}) when type in ["user", "assistant"], do: true
  defp conversation_message?(_), do: false

  @doc """
  Reads total token usage and cost from a Claude session JSONL file.
  Sums input_tokens and output_tokens from all assistant entries' message.usage,
  and total_cost_usd from result entries.
  Returns {:ok, total_tokens, total_cost_usd} or {:error, reason}.
  """
  def read_usage(session_id, project_path) do
    with_session_file(session_id, project_path, fn lines ->
      {tokens, cost} =
        Enum.reduce(lines, {0, 0.0}, fn line, {tok_acc, cost_acc} ->
          case Jason.decode(line) do
            {:ok, %{"type" => "assistant", "message" => %{"usage" => usage}}}
            when is_map(usage) ->
              input = Map.get(usage, "input_tokens") || 0
              output = Map.get(usage, "output_tokens") || 0
              {tok_acc + input + output, cost_acc}

            {:ok, %{"type" => "result", "total_cost_usd" => cost}} when is_number(cost) ->
              {tok_acc, cost_acc + cost}

            _ ->
              {tok_acc, cost_acc}
          end
        end)

      {:ok, tokens, cost}
    end)
  end

  @doc """
  Reads tool_use events from a Claude session JSONL file.
  Returns {:ok, list} where each entry is:
    %{id: String.t(), type: String.t(), message: String.t(), timestamp: String.t() | nil}
  """
  def read_tool_events(session_id, project_path) do
    with_session_file(session_id, project_path, fn lines ->
      events =
        lines
        |> Enum.map(&parse_line/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.filter(&assistant_with_tools?/1)
        |> Enum.flat_map(&extract_tool_events/1)

      {:ok, events}
    end)
  end

  defp assistant_with_tools?(%{"type" => "assistant", "message" => %{"content" => content}})
       when is_list(content) do
    Enum.any?(content, &match?(%{"type" => "tool_use"}, &1))
  end

  defp assistant_with_tools?(_), do: false

  defp extract_tool_events(%{"message" => %{"content" => content}} = entry) do
    ts = Map.get(entry, "timestamp")

    for %{"type" => "tool_use", "name" => name, "id" => tool_id} = item <- content do
      input = Map.get(item, "input", %{})

      %{
        id: tool_id,
        type: name,
        message: MessageFormatter.format_tool_call(name, input),
        timestamp: ts
      }
    end
  end

  defp extract_tool_events(_), do: []

  @doc """
  Formats messages for the UI.
  Extracts role, content, and timestamp from Claude session JSON.
  Tool result blocks from "user" messages are emitted as separate entries.
  Delegates to `EyeInTheSky.Claude.MessageFormatter`.
  """
  defdelegate format_messages(messages), to: MessageFormatter

  @doc """
  Returns a compact summary string for a tool call, suitable for chat display.
  Delegates to `EyeInTheSky.Claude.MessageFormatter`.
  """
  defdelegate format_tool_call(name, input), to: MessageFormatter
end
