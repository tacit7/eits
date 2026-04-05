defmodule EyeInTheSky.Claude.SessionReader do
  @moduledoc """
  Reads Claude Code session files from ~/.claude/projects/ and extracts conversation messages.
  """

  alias EyeInTheSky.Claude.SessionFileLocator

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
        end)

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

      result = if after_uuid, do: drop_messages_before(all_messages, after_uuid), else: all_messages
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
            {:ok, %{"type" => "assistant", "message" => %{"usage" => usage}}} when is_map(usage) ->
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
  Tool result blocks from "user" messages are emitted as separate entries.
  """
  def format_messages(messages) when is_list(messages) do
    count = Enum.count(messages)

    messages
    |> Enum.with_index()
    |> Enum.flat_map(fn {msg, idx} ->
      timestamp =
        msg["timestamp"] || msg["created_at"] ||
          DateTime.utc_now()
          |> DateTime.add(-count + idx, :second)
          |> DateTime.to_iso8601()

      tool_results = extract_tool_result_messages(msg, timestamp)

      base = %{
        uuid: msg["uuid"],
        role: get_in(msg, ["message", "role"]) || msg["type"],
        content: extract_content(msg),
        timestamp: timestamp,
        usage: get_in(msg, ["message", "usage"]),
        stream_type: nil
      }

      regular =
        if base.content == "" || String.starts_with?(String.trim(base.content), "<") do
          []
        else
          [base]
        end

      regular ++ tool_results
    end)
  end

  defp extract_tool_result_messages(
         %{"type" => "user", "message" => %{"content" => content}} = _msg,
         timestamp
       )
       when is_list(content) do
    content
    |> Enum.filter(&match?(%{"type" => "tool_result"}, &1))
    |> Enum.map(fn block ->
      tool_use_id = block["tool_use_id"] || ""
      result_content = block["content"] || ""
      body = if is_binary(result_content), do: result_content, else: Jason.encode!(result_content)
      body = String.slice(body, 0..4000)

      %{
        uuid: derive_tool_result_uuid(tool_use_id),
        role: "tool_result",
        content: body,
        timestamp: timestamp,
        usage: nil,
        stream_type: "tool_result"
      }
    end)
  end

  defp extract_tool_result_messages(_, _), do: []

  defp derive_tool_result_uuid(seed) when is_binary(seed) and seed != "" do
    hex = :crypto.hash(:sha, seed) |> Base.encode16(case: :lower)

    "#{String.slice(hex, 0, 8)}-#{String.slice(hex, 8, 4)}-#{String.slice(hex, 12, 4)}-#{String.slice(hex, 16, 4)}-#{String.slice(hex, 20, 12)}"
  end

  defp derive_tool_result_uuid(_), do: nil

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
    "> `Bash` #{cmd}"
  end

  defp format_tool_call("Task", %{"prompt" => prompt}) do
    truncated = String.slice(prompt, 0..80)
    suffix = if String.length(prompt) > 81, do: "...", else: ""
    "> `Task` #{truncated}#{suffix}"
  end

  defp format_tool_call(name, %{"message" => msg} = input)
       when is_binary(name) and is_binary(msg) do
    voice = Map.get(input, "voice", "")
    rate = Map.get(input, "rate")

    parts =
      [
        "message: #{msg}",
        if(voice != "", do: "voice: #{voice}", else: nil),
        if(rate, do: "rate: #{rate}", else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    "> `#{name}` #{parts}"
  end

  defp format_tool_call(name, input) when is_map(input) do
    summary =
      input
      |> Map.to_list()
      |> Enum.take(2)
      |> Enum.filter(fn {_k, v} -> is_binary(v) or is_number(v) or is_atom(v) end)
      |> Enum.map_join(", ", fn {k, v} ->
        val = v |> to_string() |> String.slice(0..500)
        "#{k}: #{val}"
      end)

    "> `#{name}` #{summary}"
  end

  defp format_tool_call(name, _), do: "> `#{name}`"
end
