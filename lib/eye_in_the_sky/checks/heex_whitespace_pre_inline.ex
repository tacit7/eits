defmodule EyeInTheSky.Checks.HEExWhitespacePreInline do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Tags with `whitespace-pre` or `whitespace-pre-wrap` must have their text
      content on the same line as the opening tag, not indented on the next line.

      HEEx renders the literal characters between `>` and the first expression or
      text node. Template indentation (newline + spaces) becomes visible leading
      whitespace in the browser when the parent has `whitespace-pre(-wrap)`.

      ## Wrong

          <div class="whitespace-pre-wrap">
            {String.trim(text)}
          </div>

      ## Correct

          <div class="whitespace-pre-wrap">{String.trim(text)}</div>

      ## Also wrong (multi-line <span> used for code/diff display)

          <span class="whitespace-pre font-mono">
            {@line.content}
          </span>

      ## Correct

          <span class="whitespace-pre font-mono">{@line.content}</span>
      """
    ]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params) do
    source_file
    |> Credo.SourceFile.lines()
    |> find_issues(source_file, params)
  end

  defp find_issues(lines, source_file, params) do
    lines
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [{line_no, line}, {_, next_line}] ->
      if offending?(line, next_line) do
        [issue_for(source_file, line_no, params)]
      else
        []
      end
    end)
  end

  defp offending?(line, next_line) do
    trimmed = String.trim_trailing(line)

    String.contains?(trimmed, "whitespace-pre") and
      String.ends_with?(trimmed, ">") and
      no_inline_content?(trimmed) and
      not_a_tag_open?(String.trim(next_line)) and
      String.trim(next_line) != ""
  end

  # True when there's nothing after the opening tag's closing `>`.
  # Split at the FIRST `>` — if the remainder is non-empty, content is inline.
  defp no_inline_content?(line) do
    case String.split(line, ">", parts: 2) do
      [_opening, rest] -> String.trim(rest) == ""
      _ -> true
    end
  end

  defp not_a_tag_open?(trimmed) do
    not String.starts_with?(trimmed, "<") and
      not String.starts_with?(trimmed, "<%")
  end

  defp issue_for(source_file, line_no, _params) do
    format_issue(
      source_file,
      message:
        "whitespace-pre/whitespace-pre-wrap tag has content on the next line — " <>
          "move content inline to avoid template-indentation whitespace bleeding into rendered HTML",
      line_no: line_no
    )
  end
end
