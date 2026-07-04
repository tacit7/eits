defmodule EyeInTheSky.IAM.Builtin.BlockInterpreterFileWrite do
  @moduledoc """
  Deny Bash commands that use a scripting interpreter's inline-code flag to
  write/edit a file directly (e.g. `python3 -c "open('x','w').write(...)"`),
  bypassing the tracked Edit/Write tool path.

  Two-step extract-then-search: first capture the inline-code argument
  passed to the interpreter's flag, then search *only* that captured
  argument for a language-appropriate file-write indicator. This avoids
  false-firing on commands where an interpreter flag and an unrelated
  write-looking token merely appear near each other, e.g.
  `node -e "console.log(1)" && grep -n "open('w')" legacy.py`.

  Heuristic regex matcher, not a full shell parser — supports common
  quoted/unquoted inline-code forms, not arbitrary Bash syntax, nested
  quoting, or command substitution. It is also not string-literal-aware:
  a write indicator appearing only inside a printed string (e.g.
  `node -e "console.log('writeFileSync(')"`) still matches. This tradeoff
  is accepted in favor of staying a simple, fast, deterministic matcher.

  For v1 the inline-code flag must appear immediately after the
  interpreter command (only whitespace between them). Interpreter options
  preceding the flag (`python3 -I -c ...`) and flags that are really the
  target script's own arguments (`python3 script.py -c foo`) are
  intentionally not matched.

  Supports an `"allowPatterns"` condition entry — a list of regex strings
  matched against the full command. A command matching any allowPattern
  escapes this policy.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  # Inline-code argument: a double-quoted string, a single-quoted string, or
  # a bare non-whitespace token.
  @arg_src ~S{"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\S+}

  @extractors [
    {Regex.compile!("\\bpython3?\\b[ \\t]+-c[ \\t]*(#{@arg_src})", "i"), :python},
    {Regex.compile!(
       "\\bnode\\b[ \\t]+(?:-e[ \\t]+|--eval(?:=|[ \\t]+))[ \\t]*(#{@arg_src})",
       "i"
     ), :node},
    {Regex.compile!("\\bperl\\b[ \\t]+-e[ \\t]*(#{@arg_src})", "i"), :perl},
    {Regex.compile!("\\bruby\\b[ \\t]+-e[ \\t]*(#{@arg_src})", "i"), :ruby},
    {Regex.compile!("\\bphp\\b[ \\t]+-r[ \\t]*(#{@arg_src})", "i"), :php}
  ]

  # `open(...)` / `File.open(...)` / `fopen(...)` with a write/append/create
  # mode as the second positional argument. Mode's first char must be
  # w/a/x; up to two trailing chars (b, t, +) are allowed (e.g. "wb", "a+").
  @write_mode_open_re ~r/\bopen\s*\(\s*[^,)]*,\s*["']([wWaAxX][btxBTX+]{0,2})["']/

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    if any_inline_write?(cmd) do
      not allowed?(cmd, p)
    else
      false
    end
  end

  def matches?(_, _), do: false

  defp any_inline_write?(cmd) do
    Enum.any?(@extractors, fn {re, lang} ->
      re
      |> Regex.scan(cmd, capture: :all_but_first)
      |> List.flatten()
      |> Enum.any?(&writes_file?(&1, lang))
    end)
  end

  defp writes_file?(arg, :python) do
    Regex.match?(@write_mode_open_re, arg) or
      Regex.match?(~r/\bPath\([^)]*\)\.write_(?:text|bytes)\s*\(/, arg)
  end

  defp writes_file?(arg, :node) do
    Regex.match?(~r/\bwriteFile(?:Sync)?\s*\(/, arg)
  end

  defp writes_file?(arg, :ruby) do
    Regex.match?(~r/\bFile\.write\s*\(/, arg) or Regex.match?(@write_mode_open_re, arg)
  end

  defp writes_file?(arg, :php) do
    Regex.match?(~r/\bfile_put_contents\s*\(/, arg) or Regex.match?(@write_mode_open_re, arg)
  end

  defp writes_file?(arg, :perl) do
    Regex.match?(~r/\bopen\b[^;]*?["']>{1,2}/, arg)
  end

  defp allowed?(cmd, %Policy{condition: %{} = cond}) do
    patterns = Map.get(cond, "allowPatterns") || Map.get(cond, :allowPatterns) || []

    Enum.any?(patterns, fn pat when is_binary(pat) ->
      case Regex.compile(pat) do
        {:ok, re} -> Regex.match?(re, cmd)
        _ -> false
      end
    end)
  end

  defp allowed?(_, _), do: false
end
