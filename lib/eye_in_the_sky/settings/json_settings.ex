defmodule EyeInTheSky.Settings.JsonSettings do
  @moduledoc """
  Pure logic for nested JSONB settings. No DB calls — testable without `Repo`.

  Conventions:

    * **Persisted maps store overrides only.** Never the merged effective map.
    * **Dotted keys** (e.g. `"anthropic.permission_mode"`) are accepted only at
      this boundary. Internally, code works with nested maps.
    * **Effective settings** = `app_defaults ⊕ agent_overrides ⊕ session_overrides`,
      computed on every read.

  See `EyeInTheSky.Settings.Schema` for the source of truth (types, defaults, scopes).
  """

  alias EyeInTheSky.Settings.Schema

  @type settings_map :: %{optional(String.t()) => any()}
  @type scope :: :agent | :session
  @type coerce_error ::
          :unknown_setting_key
          | :scope_not_allowed
          | :invalid_float
          | :invalid_integer
          | :invalid_enum_value
          | :type_mismatch

  # ---------------------------------------------------------------------------
  # Read / write at dotted paths
  # ---------------------------------------------------------------------------

  @doc """
  Read a nested value via dotted key. Returns `nil` when any path component is missing.
  """
  @spec get_setting(settings_map() | nil, String.t()) :: any()
  def get_setting(nil, _key), do: nil

  def get_setting(settings, dotted_key) when is_map(settings) and is_binary(dotted_key) do
    keys = String.split(dotted_key, ".")
    do_get(settings, keys)
  end

  defp do_get(value, []), do: value
  defp do_get(map, [k | rest]) when is_map(map), do: do_get(Map.get(map, k), rest)
  defp do_get(_other, _keys), do: nil

  @doc """
  Write a nested value via dotted key. Auto-creates intermediate maps.
  """
  @spec put_setting(settings_map() | nil, String.t(), any()) :: settings_map()
  def put_setting(settings, dotted_key, value) do
    keys =
      dotted_key
      |> String.split(".")
      |> Enum.map(&Access.key(&1, %{}))

    put_in(settings || %{}, keys, value)
  end

  @doc """
  Delete a nested key, then prune any newly-empty parent maps.
  """
  @spec delete_setting(settings_map() | nil, String.t()) :: settings_map()
  def delete_setting(nil, _dotted_key), do: %{}

  def delete_setting(settings, dotted_key) do
    keys =
      dotted_key
      |> String.split(".")
      |> Enum.map(&Access.key(&1, %{}))

    settings
    |> pop_in(keys)
    |> elem(1)
    |> prune_empty_maps()
  end

  defp prune_empty_maps(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {k, prune_empty_maps(v)} end)
    |> Enum.reject(fn {_k, v} -> v == %{} end)
    |> Map.new()
  end

  defp prune_empty_maps(value), do: value

  @doc """
  Drop an entire namespace (e.g. `"anthropic"`).
  """
  @spec reset_namespace(settings_map() | nil, String.t()) :: settings_map()
  def reset_namespace(nil, _namespace), do: %{}
  def reset_namespace(settings, namespace), do: Map.delete(settings, namespace)

  # ---------------------------------------------------------------------------
  # Deep merge / effective view
  # ---------------------------------------------------------------------------

  @doc """
  Recursive deep merge — right wins on leaf conflicts, but nested maps are merged
  rather than overwritten.
  """
  @spec deep_merge(any(), any()) :: any()
  def deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, lv, rv -> deep_merge(lv, rv) end)
  end

  def deep_merge(_left, right), do: right

  @doc """
  Effective settings = `Schema.defaults ⊕ agent_overrides ⊕ session_overrides`.
  """
  @spec effective_settings(settings_map() | nil, settings_map() | nil) :: settings_map()
  def effective_settings(agent_settings, session_settings) do
    Schema.defaults()
    |> deep_merge(agent_settings || %{})
    |> deep_merge(session_settings || %{})
  end

  # ---------------------------------------------------------------------------
  # Validation + coercion
  # ---------------------------------------------------------------------------

  @doc """
  Validate that the dotted key exists, that the scope is permitted for that key,
  and coerce the raw value to its declared type.
  """
  @spec coerce_value(any(), String.t(), scope()) ::
          {:ok, any()} | {:error, coerce_error()}
  def coerce_value(value, dotted_key, scope) when scope in [:agent, :session] do
    with {:ok, spec} <- Schema.fetch(dotted_key),
         :ok <- check_scope(spec, scope),
         {:ok, coerced} <- do_coerce(value, spec.type) do
      {:ok, coerced}
    end
  end

  defp check_scope(%{scopes: scopes}, scope) do
    if scope in scopes, do: :ok, else: {:error, :scope_not_allowed}
  end

  # nil / "" → nil for any *_or_nil
  defp do_coerce(nil, :float_or_nil), do: {:ok, nil}
  defp do_coerce(nil, :integer_or_nil), do: {:ok, nil}
  defp do_coerce(nil, :string_or_nil), do: {:ok, nil}
  defp do_coerce(nil, {:enum_or_nil, _}), do: {:ok, nil}

  defp do_coerce("", :float_or_nil), do: {:ok, nil}
  defp do_coerce("", :integer_or_nil), do: {:ok, nil}
  defp do_coerce("", :string_or_nil), do: {:ok, nil}
  defp do_coerce("", {:enum_or_nil, _}), do: {:ok, nil}

  # boolean
  defp do_coerce(v, :boolean) when is_boolean(v), do: {:ok, v}
  defp do_coerce("true", :boolean), do: {:ok, true}
  defp do_coerce("false", :boolean), do: {:ok, false}
  defp do_coerce("on", :boolean), do: {:ok, true}
  defp do_coerce("off", :boolean), do: {:ok, false}
  defp do_coerce(_v, :boolean), do: {:error, :type_mismatch}

  # float (strict — reject partial parses)
  defp do_coerce(v, :float_or_nil) when is_float(v), do: {:ok, v}
  defp do_coerce(v, :float_or_nil) when is_integer(v), do: {:ok, v * 1.0}

  defp do_coerce(v, :float_or_nil) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, ""} -> {:ok, f}
      _ -> {:error, :invalid_float}
    end
  end

  # integer (strict)
  defp do_coerce(v, :integer_or_nil) when is_integer(v), do: {:ok, v}

  defp do_coerce(v, :integer_or_nil) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, ""} -> {:ok, i}
      _ -> {:error, :invalid_integer}
    end
  end

  # string
  defp do_coerce(v, :string_or_nil) when is_binary(v), do: {:ok, v}

  # enum
  defp do_coerce(v, {:enum, opts}) when is_binary(v) do
    if v in opts, do: {:ok, v}, else: {:error, :invalid_enum_value}
  end

  defp do_coerce(v, {:enum_or_nil, opts}) when is_binary(v) do
    if v in opts, do: {:ok, v}, else: {:error, :invalid_enum_value}
  end

  defp do_coerce(_v, _type), do: {:error, :type_mismatch}
end
