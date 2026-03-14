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
end
