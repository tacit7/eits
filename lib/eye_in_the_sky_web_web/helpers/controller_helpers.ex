defmodule EyeInTheSkyWebWeb.ControllerHelpers do
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

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  def normalize_parent_type("sessions"), do: "session"
  def normalize_parent_type("agents"), do: "agent"
  def normalize_parent_type("tasks"), do: "task"
  def normalize_parent_type("projects"), do: "project"
  def normalize_parent_type(type), do: type

  @doc """
  Resolves a raw string to an integer ID.

  Tries Integer.parse first; on failure calls lookup_fn.(raw), which should
  return {:ok, struct_with_id} or {:ok, integer} on success, or any error
  tuple on failure.

  Returns the integer ID or nil.
  """
  def resolve_id(nil, _lookup_fn), do: nil

  def resolve_id(raw, lookup_fn) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, ""} ->
        n

      _ ->
        case lookup_fn.(raw) do
          {:ok, %{id: id}} -> id
          {:ok, id} when is_integer(id) -> id
          _ -> nil
        end
    end
  end
end
