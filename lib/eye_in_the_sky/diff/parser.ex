defmodule EyeInTheSky.Diff.Parser do
  @moduledoc """
  Parses unified diff output (from `git show` / `git diff`) into a structured
  format suitable for server-side rendering — both unified and side-by-side.

  Each parsed diff is a map:
    %{path: string, hunks: [hunk], is_binary: boolean}

  Each hunk:
    %{header: string, lines: [line]}

  Each line:
    %{type: :added | :removed | :context, content: string,
      old_line_number: integer | nil, new_line_number: integer | nil}

  Side-by-side rows are produced by `pair_lines/1`:
    [{left :: line | nil, right :: line | nil}]
  """

  @skip_prefixes [
    "diff --git",
    "index ",
    "--- ",
    "+++ ",
    "new file mode",
    "deleted file mode",
    "old mode",
    "new mode",
    "similarity index",
    "rename from",
    "rename to",
    "\\ No newline"
  ]

  @doc "Parse a raw unified diff string into a structured FileDiff map."
  def parse(raw, path \\ "") do
    if String.contains?(raw, "Binary files") and String.contains?(raw, "differ") do
      %{path: path, hunks: [], is_binary: true}
    else
      {hunks, current} =
        raw
        |> String.split("\n")
        |> Enum.map(&String.trim_trailing(&1, "\r"))
        |> Enum.reduce({[], nil}, &step/2)

      hunks = if current, do: hunks ++ [finalize(current)], else: hunks
      %{path: path, hunks: hunks, is_binary: false}
    end
  end

  @doc """
  Transforms a flat list of diff lines into side-by-side row pairs.

  Each row is {left :: line | nil, right :: line | nil}:
  - Removed lines buffer until a matching Added appears (paired 1:1).
  - Unpaired inserts: {nil, added_line}
  - Unpaired deletes: {removed_line, nil} (flushed on context or end)
  - Context: {line, line} — same line on both sides.
  """
  def pair_lines(lines) do
    {rows, buffer} =
      Enum.reduce(lines, {[], []}, fn line, {rows, buf} ->
        case line.type do
          :removed ->
            {rows, buf ++ [line]}

          :added ->
            case buf do
              [head | tail] -> {rows ++ [{head, line}], tail}
              [] -> {rows ++ [{nil, line}], []}
            end

          :context ->
            flushed = Enum.map(buf, &{&1, nil})
            {rows ++ flushed ++ [{line, line}], []}
        end
      end)

    rows ++ Enum.map(buffer, &{&1, nil})
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp step(line, {hunks, current}) do
    cond do
      skip?(line) ->
        {hunks, current}

      String.starts_with?(line, "@@") ->
        hunks = if current, do: hunks ++ [finalize(current)], else: hunks
        {hunks, parse_header(line)}

      current == nil ->
        {hunks, nil}

      String.starts_with?(line, "+") ->
        {hunks, add_line(current, :added, line)}

      String.starts_with?(line, "-") ->
        {hunks, add_line(current, :removed, line)}

      String.starts_with?(line, " ") ->
        {hunks, add_line(current, :context, line)}

      true ->
        {hunks, current}
    end
  end

  defp skip?(line) do
    Enum.any?(@skip_prefixes, &String.starts_with?(line, &1))
  end

  defp parse_header(line) do
    case Regex.run(~r/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/, line) do
      [_, old_start, new_start] ->
        %{
          header: line,
          old_line: String.to_integer(old_start),
          new_line: String.to_integer(new_start),
          lines: []
        }

      _ ->
        %{header: line, old_line: 1, new_line: 1, lines: []}
    end
  end

  defp add_line(%{old_line: _old, new_line: new, lines: lines} = hunk, :added, raw) do
    line = %{
      type: :added,
      content: String.slice(raw, 1..-1//1),
      old_line_number: nil,
      new_line_number: new
    }

    %{hunk | new_line: new + 1, lines: lines ++ [line]}
  end

  defp add_line(%{old_line: old, new_line: _new, lines: lines} = hunk, :removed, raw) do
    line = %{
      type: :removed,
      content: String.slice(raw, 1..-1//1),
      old_line_number: old,
      new_line_number: nil
    }

    %{hunk | old_line: old + 1, lines: lines ++ [line]}
  end

  defp add_line(%{old_line: old, new_line: new, lines: lines} = hunk, :context, raw) do
    line = %{
      type: :context,
      content: String.slice(raw, 1..-1//1),
      old_line_number: old,
      new_line_number: new
    }

    %{hunk | old_line: old + 1, new_line: new + 1, lines: lines ++ [line]}
  end

  defp finalize(%{header: header, lines: lines}) do
    %{header: header, lines: lines}
  end
end
