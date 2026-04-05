defmodule EyeInTheSky.Metrics.TokenParser do
  @moduledoc """
  Parses Claude JSONL session files to extract token usage data.
  Streams JSONL files, filters assistant messages, deduplicates by requestId,
  and sums token usage across all requests.
  """

  @doc """
  Parses a single JSONL file and returns aggregated token usage.

  Filters for `type == "assistant"` entries, extracts `message.usage`,
  deduplicates by `requestId` (streaming chunks repeat identical usage),
  and sums totals.

  Returns `{:ok, usage_map}` or `{:error, reason}`.
  """
  def parse_file(path) do
    if File.exists?(path) do
      usage =
        path
        |> File.stream!([], :line)
        |> Stream.map(&decode_line/1)
        |> Stream.filter(&assistant_with_usage?/1)
        |> deduplicate_by_request_id()
        |> Enum.reduce(empty_usage(), &accumulate_usage/2)

      {:ok, usage}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Parses a session's main JSONL file plus any subagent files.

  Subagent files live at `<session-uuid-dir>/subagents/agent-*.jsonl`
  relative to the main JSONL file.

  Returns `{:ok, combined_usage}` or `{:error, reason}`.
  """
  def parse_session(file_path) do
    with {:ok, main_usage} <- parse_file(file_path) do
      session_dir = String.replace_suffix(file_path, ".jsonl", "")
      subagent_dir = Path.join(session_dir, "subagents")

      {subagent_usage, subagent_count} =
        case File.ls(subagent_dir) do
          {:ok, files} ->
            agent_files =
              files
              |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
              |> Enum.map(&Path.join(subagent_dir, &1))

            usage = Enum.reduce(agent_files, empty_usage(), &merge_subagent_file/2)
            {usage, length(agent_files)}

          {:error, _} ->
            {empty_usage(), 0}
        end

      combined = merge_usage(main_usage, subagent_usage)
      combined = Map.put(combined, :subagent_count, subagent_count)

      {:ok, combined}
    end
  end

  @doc """
  Returns an empty usage accumulator.
  """
  def empty_usage do
    %{
      input_tokens: 0,
      output_tokens: 0,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      total_tokens: 0,
      request_count: 0,
      subagent_count: 0,
      models: %{}
    }
  end

  # -- Private --

  defp merge_subagent_file(path, acc) do
    case parse_file(path) do
      {:ok, u} -> merge_usage(acc, u)
      {:error, _} -> acc
    end
  end

  defp decode_line(line) do
    case Jason.decode(String.trim(line)) do
      {:ok, json} -> json
      {:error, _} -> nil
    end
  end

  defp assistant_with_usage?(nil), do: false

  defp assistant_with_usage?(
         %{"type" => "assistant", "message" => %{"usage" => _usage}} = _entry
       ),
       do: true

  defp assistant_with_usage?(_), do: false

  defp deduplicate_by_request_id(stream) do
    # Streaming chunks with the same requestId have identical usage.
    # Keep only the last entry per requestId (it has final token counts).
    stream
    |> Enum.reduce(%{}, fn entry, acc ->
      request_id = entry["requestId"] || make_ref()
      Map.put(acc, request_id, entry)
    end)
    |> Map.values()
  end

  defp accumulate_usage(entry, acc) do
    usage = get_in(entry, ["message", "usage"]) || %{}
    model = get_in(entry, ["message", "model"]) || "unknown"

    input = usage["input_tokens"] || 0
    output = usage["output_tokens"] || 0
    cache_creation = usage["cache_creation_input_tokens"] || 0
    cache_read = usage["cache_read_input_tokens"] || 0

    model_counts = Map.update(acc.models, model, 1, &(&1 + 1))

    %{
      acc
      | input_tokens: acc.input_tokens + input,
        output_tokens: acc.output_tokens + output,
        cache_creation_input_tokens: acc.cache_creation_input_tokens + cache_creation,
        cache_read_input_tokens: acc.cache_read_input_tokens + cache_read,
        total_tokens: acc.total_tokens + input + output + cache_creation + cache_read,
        request_count: acc.request_count + 1,
        models: model_counts
    }
  end

  defp merge_usage(a, b) do
    merged_models =
      Map.merge(a.models, b.models, fn _k, v1, v2 -> v1 + v2 end)

    %{
      input_tokens: a.input_tokens + b.input_tokens,
      output_tokens: a.output_tokens + b.output_tokens,
      cache_creation_input_tokens: a.cache_creation_input_tokens + b.cache_creation_input_tokens,
      cache_read_input_tokens: a.cache_read_input_tokens + b.cache_read_input_tokens,
      total_tokens: a.total_tokens + b.total_tokens,
      request_count: a.request_count + b.request_count,
      subagent_count: a.subagent_count + b.subagent_count,
      models: merged_models
    }
  end
end
