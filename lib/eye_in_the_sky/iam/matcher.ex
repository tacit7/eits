defmodule EyeInTheSky.IAM.Matcher do
  @moduledoc """
  Glob and wildcard matching for IAM policy fields.

  Public policies match via `match_glob?/2` only — regex is reserved for
  built-in policy modules via `match_regex?/2` so operators cannot construct
  catastrophic patterns via the policy form.

  Glob syntax supported:

    * `*`     — matches any run of characters *including* path separators
    * `?`     — matches exactly one character
    * `[abc]` — character class
    * literal `/` matches a path separator

  This differs slightly from shell globs (`*` does not stop at `/`) because
  project paths and URLs both benefit from the broader match.
  """

  @doc """
  `true` when `value` matches the glob `pattern`. `"*"` matches any non-nil
  value. A nil value matches only when the pattern is `"*"` or `nil`. Nil
  patterns match anything (useful for optional fields like `resource_glob`).
  """
  @spec match_glob?(String.t() | nil, String.t() | nil) :: boolean()
  def match_glob?(_value, nil), do: true
  def match_glob?(nil, "*"), do: true
  def match_glob?(nil, _), do: false
  def match_glob?(value, "*") when is_binary(value), do: true

  def match_glob?(value, pattern) when is_binary(value) and is_binary(pattern) do
    regex = glob_to_regex(pattern)
    Regex.match?(regex, value)
  end

  def match_glob?(_, _), do: false

  @doc """
  `true` when `value` matches the compiled regex. Internal use by built-in
  policy modules — not exposed to user-authored policies.
  """
  @spec match_regex?(String.t() | nil, Regex.t()) :: boolean()
  def match_regex?(nil, _), do: false

  def match_regex?(value, %Regex{} = re) when is_binary(value) do
    Regex.match?(re, value)
  end

  @doc false
  # Compile a glob pattern into an anchored regex. Exposed for tests; not part
  # of the public API.
  @spec glob_to_regex(String.t()) :: Regex.t()
  def glob_to_regex(pattern) do
    body =
      pattern
      |> String.to_charlist()
      |> escape_glob([])
      |> :erlang.iolist_to_binary()

    Regex.compile!("\\A" <> body <> "\\z")
  end

  defp escape_glob([], acc), do: Enum.reverse(acc)

  defp escape_glob([?* | rest], acc), do: escape_glob(rest, [".*" | acc])
  defp escape_glob([?? | rest], acc), do: escape_glob(rest, ["." | acc])

  defp escape_glob([?[ | rest], acc) do
    {class, tail} = take_until(rest, ?])
    escape_glob(tail, ["[" <> translate_class(class) <> "]" | acc])
  end

  defp escape_glob([c | rest], acc)
       when c in [?., ?+, ?^, ?$, ?(, ?), ?{, ?}, ?\\, ?|],
       do: escape_glob(rest, [<<?\\, c>> | acc])

  defp escape_glob([c | rest], acc), do: escape_glob(rest, [<<c>> | acc])

  defp take_until(chars, stop), do: do_take_until(chars, stop, [])

  defp do_take_until([], _, acc), do: {Enum.reverse(acc) |> :erlang.list_to_binary(), []}

  defp do_take_until([c | rest], c, acc),
    do: {Enum.reverse(acc) |> :erlang.list_to_binary(), rest}

  defp do_take_until([c | rest], stop, acc),
    do: do_take_until(rest, stop, [c | acc])

  defp translate_class(class) do
    # Inside [ ], backslash-escape regex specials. Preserve leading ! as ^.
    String.replace(class, ~r/[\\\.\+\^\$\(\)\{\}\|]/, fn m -> "\\" <> m end)
    |> replace_negation_prefix()
  end

  defp replace_negation_prefix("!" <> rest), do: "^" <> rest
  defp replace_negation_prefix(str), do: str
end
