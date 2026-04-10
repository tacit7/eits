defmodule EyeInTheSkyWeb.ControllerHelpers do
  @moduledoc "Shared helpers for API controllers and LiveViews."

  def parse_int(val), do: parse_int(val, nil)

  def parse_int(nil, default), do: default
  def parse_int(val, _default) when is_integer(val), do: val

  def parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> default
    end
  end

  def translate_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  def translate_errors(_), do: %{}

  defdelegate normalize_parent_type(type), to: EyeInTheSky.Utils.ToolHelpers

  @doc """
  Resolves a raw string to an integer ID.

  Tries Integer.parse first; on failure calls lookup_fn.(raw), which should
  return {:ok, struct_with_id} or {:ok, integer} on success, or any error
  tuple on failure.

  Returns the integer ID or nil.
  """
  def resolve_id(nil, _lookup_fn), do: nil

  def resolve_id(raw, lookup_fn) when is_binary(raw) do
    case parse_int(raw) do
      nil ->
        case lookup_fn.(raw) do
          {:ok, %{id: id}} -> id
          {:ok, id} when is_integer(id) -> id
          _ -> nil
        end

      n ->
        n
    end
  end

  @doc """
  Conditionally appends a keyword pair to `opts`.
  Skips the pair when `val` is nil or an empty string.
  """
  def maybe_opt(opts, _key, nil), do: opts
  def maybe_opt(opts, _key, ""), do: opts
  def maybe_opt(opts, key, val), do: Keyword.put(opts, key, val)

  @doc """
  Coerces a `starred` param value to a boolean.
  Accepts nil, boolean, integer (1/0), or string representations ("1"/"true").
  Returns nil if the value cannot be parsed.
  """
  def parse_starred(nil), do: nil
  def parse_starred(true), do: true
  def parse_starred(false), do: false
  def parse_starred(1), do: true
  def parse_starred(0), do: false

  def parse_starred(val) when is_binary(val) do
    case val do
      "1" -> true
      "true" -> true
      "0" -> false
      "false" -> false
      _ -> nil
    end
  end
end
