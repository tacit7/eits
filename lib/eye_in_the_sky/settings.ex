defmodule EyeInTheSky.Settings do
  @moduledoc """
  Application settings backed by the `meta` key-value table.

  Keys are namespaced with "settings." prefix to avoid collisions
  with other meta entries (e.g. api_key_anthropic).

  ## Caching

  `get/1` checks an ETS table (`:settings_cache`) before hitting the DB.
  Cache entries expire after `@cache_ttl_ms` (60 s). `put/1`, `put_many/1`,
  and `reset/1` evict affected keys immediately so readers see the new value
  within one TTL window at most.

  The ETS table must be created before the Repo starts; call
  `EyeInTheSky.Settings.init_cache/0` from `Application.start/2`.
  """

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Utils.ToolHelpers

  @prefix "settings."
  @cache_table :settings_cache
  # 60 seconds — settings change at most a few times per day
  @cache_ttl_ms 60_000

  # --- Defaults ---

  @defaults %{
    "default_model" => "sonnet",
    "cli_idle_timeout_ms" => "0",
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
    "vim_nav_enabled" => "false",
    "theme" => "dark",
    "palette_shortcut" => "auto",
    "use_anthropic_api_key" => "false",
    "rate_limit_per_session" => "false",
    "agent_notifications" => "false"
  }

  @doc """
  Creates the ETS cache table. Must be called once during application start
  before the supervision tree (and therefore the Repo) comes up.
  Safe to call multiple times — no-ops if the table already exists.
  """
  def init_cache do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:named_table, :set, :public, read_concurrency: true])

      _ ->
        @cache_table
    end
  end

  @doc "Get a single setting value, falling back to default."
  def get(key) when is_binary(key) do
    meta_key = @prefix <> key

    case cache_get(meta_key) do
      {:hit, value} ->
        value

      :miss ->
        value =
          case Repo.query("SELECT value FROM meta WHERE key = $1", [meta_key]) do
            {:ok, %{rows: [[v]]}} -> v
            _ -> Map.get(@defaults, key)
          end

        cache_put(meta_key, value)
        value
    end
  rescue
    DBConnection.ConnectionError -> Map.get(@defaults, key)
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
      val -> ToolHelpers.parse_int(val) || 0
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

    cache_evict(meta_key)
    EyeInTheSky.Events.settings_changed(key, val)

    :ok
  end

  @doc """
  Set multiple settings at once.

  Runs all upserts in a single transaction and fires one `settings_changed`
  broadcast per key — replacing the previous N-query / N-broadcast pattern.
  """
  def put_many(settings) when is_map(settings) do
    pairs =
      Enum.map(settings, fn {k, v} -> {@prefix <> to_string(k), to_string(v)} end)

    Repo.transaction(fn ->
      Enum.each(pairs, fn {meta_key, val} ->
        Repo.query!(
          """
          INSERT INTO meta (key, value, updated_at)
          VALUES ($1, $2, CURRENT_TIMESTAMP)
          ON CONFLICT(key) DO UPDATE SET value = $2, updated_at = CURRENT_TIMESTAMP
          """,
          [meta_key, val]
        )
      end)
    end)

    # Evict cache entries and broadcast after the transaction commits.
    Enum.each(pairs, fn {meta_key, val} ->
      cache_evict(meta_key)
      key = String.replace_prefix(meta_key, @prefix, "")
      EyeInTheSky.Events.settings_changed(key, val)
    end)

    :ok
  end

  @doc "Set CLI defaults. Alias for put_many/1."
  def set_cli_defaults(settings) when is_map(settings), do: put_many(settings)

  @doc "Reset a setting to its default."
  def reset(key) when is_binary(key) do
    meta_key = @prefix <> key
    Repo.query!("DELETE FROM meta WHERE key = $1", [meta_key])

    cache_evict(meta_key)
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

  @doc "Returns database info: name, size in bytes, and per-table row counts."
  def db_info do
    db_config = Application.get_env(:eye_in_the_sky, EyeInTheSky.Repo)
    db_name = db_config[:database] || "unknown"

    size =
      case Repo.query("SELECT pg_database_size(current_database())") do
        {:ok, %{rows: [[s]]}} -> s
        _ -> 0
      end

    sql = """
    SELECT 'sessions', COUNT(*) FROM sessions
    UNION ALL SELECT 'agents', COUNT(*) FROM agents
    UNION ALL SELECT 'tasks', COUNT(*) FROM tasks
    UNION ALL SELECT 'notes', COUNT(*) FROM notes
    UNION ALL SELECT 'messages', COUNT(*) FROM messages
    UNION ALL SELECT 'projects', COUNT(*) FROM projects
    UNION ALL SELECT 'commits', COUNT(*) FROM commits
    UNION ALL SELECT 'prompts', COUNT(*) FROM subagent_prompts
    """

    table_counts =
      case Repo.query!(sql) do
        %{rows: rows} -> Enum.map(rows, fn [table, count] -> {table, count} end)
      end

    %{path: db_name, size: size, table_counts: table_counts}
  end

  # ---------------------------------------------------------------------------
  # ETS cache helpers
  # ---------------------------------------------------------------------------

  defp cache_get(meta_key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@cache_table, meta_key) do
      [{^meta_key, value, expires_at}] when expires_at > now -> {:hit, value}
      _ -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache_put(meta_key, value) do
    expires_at = System.monotonic_time(:millisecond) + @cache_ttl_ms
    :ets.insert(@cache_table, {meta_key, value, expires_at})
  rescue
    ArgumentError -> :ok
  end

  defp cache_evict(meta_key) do
    :ets.delete(@cache_table, meta_key)
  rescue
    ArgumentError -> :ok
  end

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val / 1
  defp parse_float(_), do: 0.0
end
