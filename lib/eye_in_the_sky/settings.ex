defmodule EyeInTheSky.Settings do
  @moduledoc """
  Application settings backed by the `meta` key-value table.

  Keys are namespaced with "settings." prefix to avoid collisions
  with other meta entries (e.g. api_key_anthropic).
  """

  alias EyeInTheSky.Repo

  @prefix "settings."

  # --- Defaults ---

  @defaults %{
    "default_model" => "sonnet",
    "cli_idle_timeout_ms" => "300000",
    "log_claude_raw" => "false",
    "log_codex_raw" => "false",
    "tts_voice" => "Ava",
    "tts_rate" => "200",
    "pricing_opus_input" => "15.0",
    "pricing_opus_output" => "75.0",
    "pricing_opus_cache_read" => "3.75",
    "pricing_opus_cache_creation" => "18.75",
    "pricing_sonnet_input" => "3.0",
    "pricing_sonnet_output" => "15.0",
    "pricing_sonnet_cache_read" => "0.30",
    "pricing_sonnet_cache_creation" => "3.75",
    "pricing_haiku_input" => "0.80",
    "pricing_haiku_output" => "4.0",
    "pricing_haiku_cache_read" => "0.08",
    "pricing_haiku_cache_creation" => "1.00",
    "preferred_editor" => "code",
    "eits_workflow_enabled" => "true",
    "theme" => "dark"
  }

  @doc "Get a single setting value, falling back to default."
  def get(key) when is_binary(key) do
    meta_key = @prefix <> key

    case Repo.query("SELECT value FROM meta WHERE key = $1", [meta_key]) do
      {:ok, %{rows: [[value]]}} -> value
      _ -> Map.get(@defaults, key)
    end
  rescue
    _ -> Map.get(@defaults, key)
  end

  @doc "Get a setting as a float."
  def get_float(key) do
    case get(key) do
      nil -> nil
      val -> parse_float(val)
    end
  end

  @doc "Get a setting as an integer."
  def get_integer(key) do
    case get(key) do
      nil -> nil
      val -> parse_integer(val)
    end
  end

  @doc "Get a setting as a boolean."
  def get_boolean(key) do
    get(key) == "true"
  end

  @doc "Get all settings as a map with defaults merged."
  def all do
    stored =
      case Repo.query("SELECT key, value FROM meta WHERE key LIKE $1", [@prefix <> "%"]) do
        {:ok, %{rows: rows}} ->
          rows
          |> Enum.map(fn [k, v] -> {String.replace_prefix(k, @prefix, ""), v} end)
          |> Map.new()

        _ ->
          %{}
      end

    Map.merge(@defaults, stored)
  end

  @doc "Set a single setting."
  def put(key, value) when is_binary(key) do
    meta_key = @prefix <> key
    val = to_string(value)

    Repo.query!(
      """
      INSERT INTO meta (key, value, updated_at)
      VALUES ($1, $2, CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO UPDATE SET value = $2, updated_at = CURRENT_TIMESTAMP
      """,
      [meta_key, val]
    )

    EyeInTheSky.Events.settings_changed(key, val)

    :ok
  end

  @doc "Set multiple settings at once."
  def put_many(settings) when is_map(settings) do
    Enum.each(settings, fn {k, v} -> put(k, v) end)
    :ok
  end

  @doc "Set CLI defaults. Alias for put_many/1."
  def set_cli_defaults(settings) when is_map(settings), do: put_many(settings)

  @doc "Reset a setting to its default."
  def reset(key) when is_binary(key) do
    meta_key = @prefix <> key
    Repo.query!("DELETE FROM meta WHERE key = $1", [meta_key])

    EyeInTheSky.Events.settings_changed(key, Map.get(@defaults, key))

    :ok
  end

  @doc "Get pricing map in the format TokenIngestion expects."
  def pricing do
    settings = all()

    %{
      "opus" => %{
        input: parse_float(settings["pricing_opus_input"]),
        output: parse_float(settings["pricing_opus_output"]),
        cache_read: parse_float(settings["pricing_opus_cache_read"]),
        cache_creation: parse_float(settings["pricing_opus_cache_creation"])
      },
      "sonnet" => %{
        input: parse_float(settings["pricing_sonnet_input"]),
        output: parse_float(settings["pricing_sonnet_output"]),
        cache_read: parse_float(settings["pricing_sonnet_cache_read"]),
        cache_creation: parse_float(settings["pricing_sonnet_cache_creation"])
      },
      "haiku" => %{
        input: parse_float(settings["pricing_haiku_input"]),
        output: parse_float(settings["pricing_haiku_output"]),
        cache_read: parse_float(settings["pricing_haiku_cache_read"]),
        cache_creation: parse_float(settings["pricing_haiku_cache_creation"])
      }
    }
  end

  @doc "Returns the default values map."
  def defaults, do: @defaults

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val / 1
  defp parse_float(_), do: 0.0

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> 0
    end
  end

  defp parse_integer(val) when is_integer(val), do: val
  defp parse_integer(_), do: 0
end
