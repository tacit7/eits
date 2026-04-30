defmodule EyeInTheSkyWeb.ControllerHelpers do
  @moduledoc "Shared helpers for API controllers and LiveViews."

  @doc """
  Canonical string-to-integer parser. **Do not use `Integer.parse/1` directly.**
  Returns the integer or `nil` (1-arg) / `default` (2-arg) on failure.
  Import via: `import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]`
  """
  def parse_int(val), do: EyeInTheSky.Utils.ToolHelpers.parse_int(val)
  def parse_int(val, default), do: EyeInTheSky.Utils.ToolHelpers.parse_int(val, default)

  @doc "Trim a param value only when it is a binary; pass through nil and non-string types unchanged."
  def trim_param(v) when is_binary(v), do: String.trim(v)
  def trim_param(v), do: v

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

  # Accept an already-resolved integer (e.g. from JSON body where session_id was sent as a number)
  def resolve_id(n, _lookup_fn) when is_integer(n), do: n

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
  Returns `:ok` when `val` is present (non-nil, non-empty string);
  `{:error, :bad_request, msg}` otherwise.
  """
  def validate_required(nil, field), do: {:error, :bad_request, "#{field} is required"}
  def validate_required("", field), do: {:error, :bad_request, "#{field} is required"}
  def validate_required(_val, _field), do: :ok

  @doc """
  Coerces a `starred` param value to a boolean.
  Accepts boolean, integer (1/0), or string representations ("1"/"true"/"0"/"false").

  Returns `{:ok, bool}` on success or `:error` when the value is absent or unrecognisable.
  """
  def parse_starred(nil), do: :error
  def parse_starred(true), do: {:ok, true}
  def parse_starred(false), do: {:ok, false}
  def parse_starred(val) when is_integer(val), do: {:ok, val != 0}

  def parse_starred(val) when is_binary(val) do
    case val do
      v when v in ["1", "true"] -> {:ok, true}
      v when v in ["0", "false"] -> {:ok, false}
      _ -> :error
    end
  end
end
