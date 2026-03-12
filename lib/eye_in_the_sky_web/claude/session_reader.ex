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

  # NOTE: This is lossy for paths containing hyphens (e.g., /Users/foo/my-app
  # escapes to -Users-foo-my-app, but my-app's hyphen is indistinguishable
  # from a path separator). Fundamentally ambiguous without a lookup table.
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
  Reads messages from a session file that come after the given uuid.
  If after_uuid is nil, reads all messages. Used for incremental sync.
  """
  def read_messages_after_uuid(session_id, project_path, after_uuid) do
    case find_session_file(session_id, project_path) do
      {:ok, file_path} -> parse_session_file_after(file_path, after_uuid)
      {:error, _} = error -> error
    end
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
          |> Enum.take(-limit)

        {:ok, messages}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_session_file_after(file_path, nil) do
    # No cursor; read everything
    parse_session_file(file_path, 999_999)
  end

  defp parse_session_file_after(file_path, after_uuid) do
    case File.read(file_path) do
      {:ok, content} ->
        lines = String.split(content, "\n", trim: true)

        all_messages =
          lines
          |> Enum.map(&parse_line/1)
          |> Enum.filter(&is_conversation_message?/1)

        # Find cursor position; if UUID not found (e.g. after context compaction),
        # fall back to returning all messages rather than returning empty.
        messages =
          case Enum.find_index(all_messages, fn msg -> msg["uuid"] == after_uuid end) do
            nil -> all_messages
            idx -> Enum.drop(all_messages, idx + 1)
          end

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
  Reads tool_use events from a Claude session JSONL file.
  Returns {:ok, list} where each entry is:
    %{id: String.t(), type: String.t(), message: String.t(), timestamp: String.t() | nil}
  """
  def read_tool_events(session_id, project_path) do
    case find_session_file(session_id, project_path) do
      {:ok, file_path} ->
        case File.read(file_path) do
          {:ok, content} ->
            events =
              content
              |> String.split("\n", trim: true)
              |> Enum.map(&parse_line/1)
              |> Enum.reject(&is_nil/1)
              |> Enum.filter(&is_assistant_with_tools?/1)
              |> Enum.flat_map(&extract_tool_events/1)

            {:ok, events}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} = err ->
        err
    end
  end

  defp is_assistant_with_tools?(%{"type" => "assistant", "message" => %{"content" => content}})
       when is_list(content) do
    Enum.any?(content, &match?(%{"type" => "tool_use"}, &1))
  end

  defp is_assistant_with_tools?(_), do: false

  defp extract_tool_events(%{"message" => %{"content" => content}} = entry) do
    ts = Map.get(entry, "timestamp")

    content
    |> Enum.filter(&match?(%{"type" => "tool_use"}, &1))
    |> Enum.map(fn %{"name" => name, "id" => tool_id} = item ->
      input = Map.get(item, "input", %{})

      %{
        id: tool_id,
        type: name,
        message: format_tool_call(name, input),
        timestamp: ts
      }
    end)
  end

  defp extract_tool_events(_), do: []

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
        uuid: msg["uuid"],
        role: get_in(msg, ["message", "role"]) || msg["type"],
        content: extract_content(msg),
        timestamp: timestamp,
        usage: get_in(msg, ["message", "usage"])
      }
    end)
    |> Enum.reject(fn msg ->
      msg.content == "" || String.starts_with?(String.trim(msg.content), "<")
    end)
  end

  defp extract_content(%{"message" => %{"content" => content}}) when is_binary(content) do
    content
  end

  defp extract_content(%{"message" => %{"content" => content}}) when is_list(content) do
    content
    |> Enum.filter(&is_map/1)
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => text} ->
        [text]

      %{"type" => "tool_use", "name" => name, "input" => input} ->
        [format_tool_call(name, input)]

      _ ->
        []
    end)
    |> Enum.join("\n\n")
  end

  # Handle case where content is directly in message (not nested)
  defp extract_content(%{"content" => content}) when is_binary(content) do
    content
  end

  defp extract_content(%{"content" => content}) when is_list(content) do
    content
    |> Enum.filter(&is_map/1)
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => text} ->
        [text]

      %{"type" => "tool_use", "name" => name, "input" => input} ->
        [format_tool_call(name, input)]

      _ ->
        []
    end)
    |> Enum.join("\n\n")
  end

  defp extract_content(_), do: ""

  # Tool call formatting - compact summaries for chat display
  defp format_tool_call("Read", %{"file_path" => path}), do: "> `Read` #{path}"
  defp format_tool_call("Write", %{"file_path" => path}), do: "> `Write` #{path}"
  defp format_tool_call("Edit", %{"file_path" => path}), do: "> `Edit` #{path}"
  defp format_tool_call("Glob", %{"pattern" => pat}), do: "> `Glob` #{pat}"

  defp format_tool_call("Grep", %{"pattern" => pat} = input) do
    path = input["path"] || ""
    "> `Grep` `#{pat}` #{path}"
  end

  defp format_tool_call("Bash", %{"command" => cmd}) do
    truncated = String.slice(cmd, 0..120)
    suffix = if String.length(cmd) > 121, do: "...", else: ""
    "> `Bash` `#{truncated}#{suffix}`"
  end

  defp format_tool_call("Task", %{"prompt" => prompt}) do
    truncated = String.slice(prompt, 0..80)
    suffix = if String.length(prompt) > 81, do: "...", else: ""
    "> `Task` #{truncated}#{suffix}"
  end

  defp format_tool_call(name, input) when is_map(input) do
    summary =
      input
      |> Map.to_list()
      |> Enum.take(2)
      |> Enum.filter(fn {_k, v} -> is_binary(v) or is_number(v) or is_atom(v) end)
      |> Enum.map(fn {k, v} ->
        val = v |> to_string() |> String.slice(0..60)
        "#{k}: #{val}"
      end)
      |> Enum.join(", ")

    "> `#{name}` #{summary}"
  end

  defp format_tool_call(name, _), do: "> `#{name}`"
end
