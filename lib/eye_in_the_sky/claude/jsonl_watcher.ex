defmodule EyeInTheSky.Claude.JsonlWatcher do
  @moduledoc """
  GenServer that watches a Claude Code session's JSONL transcript file for
  appends and runs `SessionImporter.sync/3` when it changes.

  One watcher per DmLive view. Started in `mount/3` (connected branch only)
  and stopped in `terminate/2`. Crashes are isolated — if the watcher dies
  the LiveView keeps working, just without real-time JSONL updates.

  Why a file watcher and not a poll?

    - The Claude Code CLI appends to the JSONL on every assistant turn, tool
      use, and (with `--include-partial-messages`) every text delta. A file
      watcher gets the event ~immediately after the write; polling adds
      latency and burns CPU when idle.
    - The Stop hook is unreliable (annotation gate, async background, hook
      misconfig). The JSONL write is the canonical event.
    - PostToolUse hook → REST round-trip is also fine, but adds a network
      hop for something the kernel can tell us about for free.

  Debouncing: bursts of writes (multi-line tool output) trigger many
  file_event messages. We debounce with a 200ms timer so we run sync once
  per burst rather than per line.
  """

  use GenServer

  alias EyeInTheSky.Claude.{SessionFileLocator, SessionImporter}

  require Logger

  @debounce_ms 200

  # ---------------------------------------------------------------------------
  # Client
  # ---------------------------------------------------------------------------

  @doc """
  Starts a watcher for the given session.

  Required opts:
    * `:session_id`   — integer session id (used by SessionImporter)
    * `:session_uuid` — Claude session UUID (used to locate the JSONL file)
    * `:project_path` — resolved project path (used to escape the dir name)
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Stops the watcher gracefully (idempotent)."
  def stop(pid) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000), else: :ok
  end

  def stop(_), do: :ok

  # ---------------------------------------------------------------------------
  # Server
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    # Trap exits so the FileSystem watcher dying doesn't take us (or the
    # LiveView linked above us) down. We fall back to inert state instead.
    Process.flag(:trap_exit, true)

    session_id = Keyword.fetch!(opts, :session_id)
    session_uuid = Keyword.fetch!(opts, :session_uuid)
    project_path = Keyword.fetch!(opts, :project_path)

    file_path =
      case SessionFileLocator.locate(session_uuid, project_path) do
        {:ok, path} -> path
        # File doesn't exist yet — Claude will create it on first turn. Watch
        # the parent directory so we still get events when it appears.
        {:error, :not_found} -> nil
      end

    watch_dir =
      case file_path do
        nil ->
          home = System.get_env("HOME")
          escaped = SessionFileLocator.escape_project_path(project_path)
          Path.join([home, ".claude", "projects", escaped])

        path ->
          Path.dirname(path)
      end

    case ensure_watcher(watch_dir) do
      {:ok, watcher_pid} ->
        FileSystem.subscribe(watcher_pid)

        state = %{
          session_id: session_id,
          session_uuid: session_uuid,
          project_path: project_path,
          file_path: file_path,
          watcher_pid: watcher_pid,
          debounce_ref: nil
        }

        Logger.debug(
          "JsonlWatcher started session=#{session_id} watching=#{inspect(watch_dir)}"
        )

        {:ok, state}

      {:error, reason} ->
        Logger.warning(
          "JsonlWatcher: failed to start FileSystem for #{watch_dir}: #{inspect(reason)}"
        )

        :ignore
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, _events}}, state) do
    if relevant_path?(path, state) do
      {:noreply, schedule_sync(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    Logger.warning(
      "JsonlWatcher: FileSystem watcher stopped for session=#{state.session_id}"
    )

    {:stop, :normal, state}
  end

  def handle_info(:run_sync, state) do
    do_sync(state)
    {:noreply, %{state | debounce_ref: nil}}
  end

  # FileSystem watcher died — log and stop quietly so the LiveView keeps living.
  def handle_info({:EXIT, pid, reason}, %{watcher_pid: pid} = state) do
    Logger.warning(
      "JsonlWatcher: FileSystem exited session=#{state.session_id} reason=#{inspect(reason)}"
    )

    {:stop, :normal, state}
  end

  # Any other linked process (the LiveView) died — shut down cleanly.
  def handle_info({:EXIT, _other, _reason}, state), do: {:stop, :normal, state}

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # If we know the exact JSONL path, only react to events on that file.
  # Otherwise (file didn't exist at init), accept any .jsonl event in the
  # directory and lock onto our session's file once we see it.
  defp relevant_path?(path, %{file_path: nil, session_uuid: uuid}) do
    String.ends_with?(path, "#{uuid}.jsonl")
  end

  defp relevant_path?(path, %{file_path: file_path}), do: path == file_path

  defp schedule_sync(state) do
    if state.debounce_ref, do: Process.cancel_timer(state.debounce_ref)
    ref = Process.send_after(self(), :run_sync, @debounce_ms)
    %{state | debounce_ref: ref}
  end

  defp do_sync(%{
         session_id: session_id,
         session_uuid: session_uuid,
         project_path: project_path
       }) do
    SessionImporter.sync(session_uuid, project_path, session_id)
  rescue
    e ->
      Logger.warning(
        "JsonlWatcher sync failed session=#{session_id}: #{Exception.message(e)}"
      )
  catch
    :exit, reason ->
      Logger.warning(
        "JsonlWatcher sync exited session=#{session_id}: #{inspect(reason)}"
      )
  end

  defp ensure_watcher(watch_dir) do
    File.mkdir_p!(watch_dir)
    FileSystem.start_link(dirs: [watch_dir])
  end
end
