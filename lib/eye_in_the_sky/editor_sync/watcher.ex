defmodule EyeInTheSky.EditorSync.Watcher do
  @moduledoc """
  GenServer that watches a temp file for changes and syncs them back to the DB.

  One watcher per record. Keyed in `EyeInTheSky.EditorSync.Registry` under
  `{:editor_sync, type, record_id}`.

  Poll loop:
  - Every `poll_interval_ms` (default 500) it stats the file.
  - If content has changed (SHA-256 hash differs), it reloads the record by ID
    and writes the updated field back to the DB.
  - After `idle_timeout_ms` (default 30 minutes) with no content changes, it
    stops silently.
  - Tolerates up to 5 consecutive missing polls (atomic-save behavior) before
    stopping.

  Both intervals are injected via start_link opts so tests can use fast values.
  """

  use GenServer, restart: :temporary

  require Logger

  alias EyeInTheSky.Events
  alias EyeInTheSky.Notes
  alias EyeInTheSky.Prompts
  alias EyeInTheSky.Tasks

  @default_poll_ms 500
  @default_idle_ms 30 * 60 * 1_000
  @max_missing 5

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    {type, opts} = Keyword.pop!(opts, :type)
    {record_id, opts} = Keyword.pop!(opts, :record_id)
    {tmp_path, opts} = Keyword.pop!(opts, :tmp_path)
    {initial_hash, opts} = Keyword.pop!(opts, :initial_hash)
    poll_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_ms)
    idle_ms = Keyword.get(opts, :idle_timeout_ms, @default_idle_ms)

    state = %{
      type: type,
      record_id: record_id,
      tmp_path: tmp_path,
      last_hash: initial_hash,
      last_mtime: nil,
      last_size: nil,
      last_change_ms: System.monotonic_time(:millisecond),
      missing_count: 0,
      poll_interval_ms: poll_ms,
      idle_timeout_ms: idle_ms
    }

    name = {:via, Registry, {EyeInTheSky.EditorSync.Registry, {type, record_id}}}
    GenServer.start_link(__MODULE__, state, name: name)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(state) do
    schedule_poll(state.poll_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = do_poll(state)
    schedule_poll(state.poll_interval_ms)
    {:noreply, state}
  end

  def handle_info(:stop, state) do
    {:stop, :normal, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_poll(state) do
    case File.stat(state.tmp_path, time: :posix) do
      {:error, :enoent} ->
        count = state.missing_count + 1

        if count >= @max_missing do
          Logger.debug("[EditorSync.Watcher] file gone after #{count} misses, stopping type=#{state.type} id=#{state.record_id}")

          stop_self()
          state
        else
          %{state | missing_count: count}
        end

      {:ok, stat} ->
        state = %{state | missing_count: 0}
        check_content(state, stat)

      {:error, reason} ->
        Logger.warning("[EditorSync.Watcher] stat error: #{inspect(reason)}")
        state
    end
  end

  defp check_content(state, stat) do
    # Fast path: skip if mtime+size unchanged
    if stat.mtime == state.last_mtime && stat.size == state.last_size do
      maybe_idle_stop(state)
    else
      case File.read(state.tmp_path) do
        {:error, _} ->
          state

        {:ok, content} ->
          hash = :crypto.hash(:sha256, content)

          if hash == state.last_hash do
            # Content unchanged even though mtime/size shifted (e.g. touch)
            maybe_idle_stop(%{state | last_mtime: stat.mtime, last_size: stat.size})
          else
            sync_to_db(state, content, hash, stat)
          end
      end
    end
  end

  defp sync_to_db(state, content, hash, stat) do
    case reload_record(state.type, state.record_id) do
      nil ->
        Logger.warning("[EditorSync.Watcher] record deleted mid-watch type=#{state.type} id=#{state.record_id}")

        Events.editor_sync_failed(state.type, state.record_id, :record_deleted)
        stop_self()
        state

      record ->
        attrs = update_attrs_for(state.type, content)

        case do_update(state.type, record, attrs) do
          {:ok, updated} ->
            broadcast_updated(state.type, updated)

            %{
              state
              | last_hash: hash,
                last_mtime: stat.mtime,
                last_size: stat.size,
                last_change_ms: System.monotonic_time(:millisecond)
            }

          {:error, reason} ->
            Logger.error("[EditorSync.Watcher] DB write failed: #{inspect(reason)} type=#{state.type} id=#{state.record_id}")

            Events.editor_sync_failed(state.type, state.record_id, reason)
            stop_self()
            state
        end
    end
  end

  defp maybe_idle_stop(state) do
    elapsed = System.monotonic_time(:millisecond) - state.last_change_ms

    if elapsed > state.idle_timeout_ms do
      Logger.debug("[EditorSync.Watcher] idle timeout, stopping type=#{state.type} id=#{state.record_id}")

      stop_self()
    end

    state
  end

  defp reload_record(:note, id), do: Notes.get_note(id) |> unwrap_ok()
  defp reload_record(:prompt, id), do: Prompts.get_prompt(id) |> unwrap_ok()
  defp reload_record(:task, id), do: Tasks.get_task(id) |> unwrap_ok()

  defp unwrap_ok({:ok, r}), do: r
  defp unwrap_ok(_), do: nil

  defp update_attrs_for(:note, content), do: %{body: content}
  defp update_attrs_for(:prompt, content), do: %{prompt_text: content}
  defp update_attrs_for(:task, content), do: %{description: content}

  defp do_update(:note, record, attrs), do: Notes.update_note(record, attrs)
  defp do_update(:prompt, record, attrs), do: Prompts.update_prompt(record, attrs)
  defp do_update(:task, record, attrs), do: Tasks.update_task(record, attrs)

  defp broadcast_updated(:note, record), do: Events.note_updated(record)
  defp broadcast_updated(:prompt, record), do: Events.prompt_updated(record)
  defp broadcast_updated(:task, record), do: Events.task_updated(record)

  defp schedule_poll(ms), do: Process.send_after(self(), :poll, ms)

  defp stop_self, do: Process.send(self(), :stop, [])
end
