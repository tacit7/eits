defmodule EyeInTheSkyWeb.Claude.SessionReader do
  @moduledoc """
  Reads Claude Code session files from ~/.claude/projects/ and extracts conversation messages.
  """

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
        files
        |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
        |> Enum.map(fn filename ->
          session_id = String.replace_suffix(filename, ".jsonl", "")
          file_path = Path.join(project_path, filename)
          file_stat = File.stat!(file_path)

          %{
            session_id: session_id,
            project_path: unescape_project_path(escaped_project_name),
            last_modified: file_stat.mtime,
            file_size: file_stat.size,
            discovered: true
          }
        end)

      {:error, _} ->
        []
    end
  end

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
    case find_session_file(session_id, project_path) do
      {:ok, file_path} ->
        parse_session_file(file_path, limit)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Finds the Claude session JSONL file path.
  Claude stores sessions in: ~/.claude/projects/<escaped-project-path>/<session-id>.jsonl
  """
  def find_session_file(session_id, project_path) do
    home = System.get_env("HOME")
    escaped_path = escape_project_path(project_path)
    file_path = Path.join([home, ".claude", "projects", escaped_path, "#{session_id}.jsonl"])

    if File.exists?(file_path) do
      {:ok, file_path}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Escapes project path for Claude's directory naming convention.
  Example: "/Users/user/projects/myapp" -> "-Users-user-projects-myapp"
  """
  def escape_project_path(path) do
    path
    |> String.replace("/", "-")
  end

  @doc """
  Parses a Claude session JSONL file and extracts conversation messages.
  Returns the last N messages in chronological order.
  """
  def parse_session_file(file_path, limit) do
    case File.read(file_path) do
      {:ok, content} ->
        messages =
          content
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_line/1)
          |> Enum.filter(&is_conversation_message?/1)
          # Get last N messages
          |> Enum.take(-limit)

        {:ok, messages}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_line(line) do
    case Jason.decode(line) do
      {:ok, json} -> json
      {:error, _} -> nil
    end
  end

  defp is_conversation_message?(nil), do: false
  defp is_conversation_message?(%{"type" => type}) when type in ["user", "assistant"], do: true
  defp is_conversation_message?(_), do: false

  @doc """
  Formats messages for the UI.
  Extracts role, content, and timestamp from Claude session JSON.
  Filters out messages with empty content (tool results).
  """
  def format_messages(messages) when is_list(messages) do
    messages
    |> Enum.with_index()
    |> Enum.map(fn {msg, idx} ->
      # Use timestamp from message, or generate one based on index
      # (assuming messages are in chronological order)
      timestamp =
        msg["timestamp"] || msg["created_at"] ||
          DateTime.utc_now()
          |> DateTime.add(-Enum.count(messages) + idx, :second)
          |> DateTime.to_iso8601()

      %{
        role: get_in(msg, ["message", "role"]) || msg["type"],
        content: extract_content(msg),
        timestamp: timestamp
      }
    end)
    |> Enum.reject(&(&1.content == ""))
  end

  defp extract_content(%{"message" => %{"content" => content}}) when is_binary(content) do
    content
  end

  defp extract_content(%{"message" => %{"content" => content}}) when is_list(content) do
    # Handle structured content (text blocks, tool calls, etc.)
    content
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn block ->
      case block do
        %{"type" => "text", "text" => text} -> text
        %{"type" => "tool_use", "name" => name} -> "[Tool: #{name}]"
        # Skip tool results
        %{"type" => "tool_result"} -> ""
        %{"text" => text} -> text
        _ -> ""
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  # Handle case where content is directly in message (not nested)
  defp extract_content(%{"content" => content}) when is_binary(content) do
    content
  end

  defp extract_content(%{"content" => content}) when is_list(content) do
    content
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn block ->
      case block do
        %{"type" => "text", "text" => text} -> text
        %{"type" => "tool_use", "name" => name} -> "[Tool: #{name}]"
        # Skip tool results
        %{"type" => "tool_result"} -> ""
        %{"text" => text} -> text
        _ -> ""
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp extract_content(_), do: ""
end
