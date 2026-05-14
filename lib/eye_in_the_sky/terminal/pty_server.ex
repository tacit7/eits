defmodule EyeInTheSky.Terminal.PtyServer do
  @moduledoc """
  GenServer that owns a single PTY session via erlexec.

  ## Persistent lifecycle

  PtyServer is no longer tied to a single LiveView pid. It lives under
  PtySupervisor and is keyed by a `session_key` string in PtyRegistry.
  Multiple LiveViews (or the same one after navigation) can subscribe and
  unsubscribe without killing the underlying OS process.

  The PTY shuts down only when:
  - The OS process exits (shell/Claude exits).
  - All subscribers have been gone for longer than `idle_timeout_ms` (default 30 min).
  - `stop/1` is called explicitly.

  ## Scroll buffer

  Output is accumulated in a capped binary buffer (default 512 KB). On
  subscribe, the caller immediately receives `{:pty_scroll_buffer, tag, binary}`
  (or `{:pty_scroll_buffer, binary}` when tag is nil) so it can replay history
  into xterm.js before live output begins.

  ## Subscriber messages

  Each subscriber pid receives:
  - `{:pty_scroll_buffer, binary}` — history replayed on subscribe (no tag)
  - `{:pty_scroll_buffer, tag, binary}` — same, with tag
  - `{:pty_output, binary}` — live PTY output (no tag)
  - `{:pty_output, tag, binary}` — live PTY output with tag
  - `:pty_exited` — OS process has exited (no tag)
  - `{:pty_exited, tag}` — OS process has exited with tag

  ## Tagged subscribers

  Pass a tag to `subscribe/3` to route output from multiple PTYs through a
  single LiveView. The tag is included in all messages so the LiveView can
  dispatch to the right component:

      PtyServer.subscribe(pty_pid, self(), canvas_terminal_id)

  ## erlexec gotchas on macOS

  - Pass the command as a **list** (not a string). A string triggers `m_shell=true`
    in erlexec's C port, wrapping the command as `$SHELL -c "cmd"`. That causes
    bash to be run as a sub-shell of sh -c, which exits immediately.

  - Include `:stdin` in the opts. Without it, erlexec defaults stdin to /dev/null.
    Bash reads EOF and exits cleanly (code 0) before accepting any input.

  - PTYs start with echo disabled unless `:pty_echo` (or equivalent termios opts)
    is set. Without it, typed characters are sent to bash and commands execute,
    but the user sees a blank terminal while typing.

  - `{:winsz, {rows, cols}}` is a valid exec:run option (2-element nested tuple),
    but we call :exec.winsz/3 after spawn instead to keep the opts list simpler.

  - When bash exits with code 0, erlexec sends `{:DOWN, os_pid, :process, lwp, :normal}`
    (not `{:exit_status, 0}`). The `:normal` clause handles this case.
  """

  use GenServer, restart: :temporary

  require Logger

  @default_cols 220
  @default_rows 50
  @shell_bin System.find_executable("zsh") || System.find_executable("bash") || "/bin/zsh"

  # 512 KB scroll buffer cap
  @max_buffer_bytes 512 * 1024
  # 30 minutes idle before auto-shutdown when no subscribers
  @default_idle_timeout_ms 30 * 60 * 1_000

  # --- Public API ---

  @doc """
  Start a PtyServer registered under `session_key` in PtyRegistry.

  Options:
  - `:session_key` (required) — unique string key for registry lookup
  - `:cols` — initial terminal width (default #{@default_cols})
  - `:rows` — initial terminal height (default #{@default_rows})
  - `:command` — command list to spawn (default: bash interactive)
  - `:idle_timeout_ms` — ms with no subscribers before stopping (default #{@default_idle_timeout_ms})
  """
  def start_link(opts) do
    session_key = Keyword.fetch!(opts, :session_key)
    name = {:via, Registry, {EyeInTheSky.Terminal.PtyRegistry, session_key}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribe `pid` to receive PTY output. Immediately sends the scroll buffer.

  Pass an optional `tag` to receive tagged messages (`{:pty_output, tag, data}`
  instead of `{:pty_output, data}`). Useful when one LiveView manages multiple
  PTY sessions and needs to route output to the right component.
  """
  def subscribe(server, pid \\ self(), tag \\ nil) do
    GenServer.call(server, {:subscribe, pid, tag})
  end

  @doc "Unsubscribe `pid` from PTY output."
  def unsubscribe(server, pid \\ self()) do
    GenServer.cast(server, {:unsubscribe, pid})
  end

  @doc "Write data (keystrokes / paste) into the PTY."
  def write(server, data), do: GenServer.cast(server, {:write, data})

  @doc "Resize the PTY window."
  def resize(server, cols, rows), do: GenServer.cast(server, {:resize, cols, rows})

  @doc "Terminate the PTY and the GenServer."
  def stop(server), do: GenServer.stop(server, :normal)

  @doc "Returns true if the PTY was started within the last 10 seconds."
  def fresh?(server), do: GenServer.call(server, :fresh?)

  # --- Callbacks ---

  @impl true
  def init(opts) do
    cols = Keyword.get(opts, :cols, @default_cols)
    rows = Keyword.get(opts, :rows, @default_rows)
    idle_timeout_ms = Keyword.get(opts, :idle_timeout_ms, @default_idle_timeout_ms)
    command = Keyword.get(opts, :command, default_shell_cmd())

    home = System.get_env("HOME", "/tmp")

    env = [
      {"TERM", "xterm-256color"},
      # Signal truecolor support — chalk uses this to select level 3 (24-bit)
      {"COLORTERM", "truecolor"},
      # Bypass chalk/supports-color isTTY gate. Without this, chalk level is 0
      # even with COLORTERM set because erlexec stdout is not a real TTY from
      # Node's perspective. FORCE_COLOR=3 skips the isTTY check entirely.
      {"FORCE_COLOR", "3"},
      {"LANG", "en_US.UTF-8"},
      {"HOME", home},
      {"PATH", System.get_env("PATH", "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")},
      {"SHELL", @shell_bin},
      {"USER", System.get_env("USER", "user")},
      {"LOGNAME", System.get_env("LOGNAME", System.get_env("USER", "user"))}
    ]

    exec_opts = [
      :stdin,
      {:stdout, self()},
      {:stderr, :stdout},
      :pty,
      :pty_echo,
      {:env, env},
      :monitor
    ]

    case :exec.run(command, exec_opts) do
      {:ok, _erlang_pid, os_pid} ->
        :exec.winsz(os_pid, rows, cols)

        state = %{
          os_pid: os_pid,
          cols: cols,
          rows: rows,
          # %{pid => tag_or_nil}
          subscribers: %{},
          scroll_buffer: [],
          scroll_buffer_bytes: 0,
          idle_timeout_ms: idle_timeout_ms,
          idle_timer: nil,
          started_at: System.monotonic_time(:millisecond)
        }

        {:ok, arm_idle_timer(state)}

      {:error, reason} ->
        Logger.error("PtyServer: failed to spawn #{inspect(command)}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:fresh?, _from, state) do
    age_ms = System.monotonic_time(:millisecond) - state.started_at
    {:reply, age_ms < 10_000, state}
  end

  @impl true
  def handle_call({:subscribe, pid, tag}, _from, state) do
    Process.monitor(pid)
    state = %{state | subscribers: Map.put(state.subscribers, pid, tag)}
    state = cancel_idle_timer(state)

    buffer = IO.iodata_to_binary(state.scroll_buffer)
    send_to(pid, tag, :scroll_buffer, buffer)

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:unsubscribe, pid}, state) do
    {:noreply, remove_subscriber(state, pid)}
  end

  def handle_cast({:write, data}, %{os_pid: os_pid} = state) do
    :exec.send(os_pid, data)
    {:noreply, state}
  end

  def handle_cast({:resize, cols, rows}, %{os_pid: os_pid} = state) do
    :exec.winsz(os_pid, rows, cols)
    {:noreply, %{state | cols: cols, rows: rows}}
  end

  @impl true
  # Live PTY output from erlexec
  def handle_info({:stdout, _os_pid, data}, state) do
    state = append_scroll_buffer(state, data)
    broadcast(state.subscribers, :output, data)
    {:noreply, state}
  end

  # erlexec: OS process exited with non-zero status
  def handle_info({:DOWN, _ref, :process, _pid, {:exit_status, _code}}, state) do
    broadcast(state.subscribers, :exited, nil)
    {:stop, :normal, state}
  end

  # erlexec: OS process exited cleanly (exit code 0 → :normal)
  def handle_info({:DOWN, os_pid, :process, _lwp, :normal}, %{os_pid: os_pid} = state) do
    broadcast(state.subscribers, :exited, nil)
    {:stop, :normal, state}
  end

  # Subscriber process died — remove it
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, remove_subscriber(state, pid)}
  end

  # Idle timeout fired — no subscribers long enough, shut down
  def handle_info(:idle_timeout, state) do
    if map_size(state.subscribers) == 0 do
      Logger.info("PtyServer: idle timeout with no subscribers, shutting down")
      {:stop, :normal, state}
    else
      {:noreply, %{state | idle_timer: nil}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{os_pid: os_pid}) do
    :exec.stop(os_pid)
  rescue
    _ -> :ok
  end

  # --- Private ---

  defp default_shell_cmd, do: [@shell_bin, "-i"]

  # Broadcast a typed message to all subscribers, including tag when set.
  defp broadcast(subscribers, type, payload) do
    Enum.each(subscribers, fn {pid, tag} ->
      send_to(pid, tag, type, payload)
    end)
  end

  defp send_to(pid, nil, :scroll_buffer, data), do: send(pid, {:pty_scroll_buffer, data})
  defp send_to(pid, tag, :scroll_buffer, data), do: send(pid, {:pty_scroll_buffer, tag, data})
  defp send_to(pid, nil, :output, data), do: send(pid, {:pty_output, data})
  defp send_to(pid, tag, :output, data), do: send(pid, {:pty_output, tag, data})
  defp send_to(pid, nil, :exited, _), do: send(pid, :pty_exited)
  defp send_to(pid, tag, :exited, _), do: send(pid, {:pty_exited, tag})

  defp remove_subscriber(state, pid) do
    updated = %{state | subscribers: Map.delete(state.subscribers, pid)}

    if map_size(updated.subscribers) == 0 do
      arm_idle_timer(updated)
    else
      updated
    end
  end

  defp arm_idle_timer(%{idle_timeout_ms: ms} = state) do
    timer = Process.send_after(self(), :idle_timeout, ms)
    %{state | idle_timer: timer}
  end

  defp cancel_idle_timer(%{idle_timer: nil} = state), do: state

  defp cancel_idle_timer(%{idle_timer: ref} = state) do
    Process.cancel_timer(ref)
    %{state | idle_timer: nil}
  end

  defp append_scroll_buffer(%{scroll_buffer_bytes: current} = state, data) do
    data_size = byte_size(data)
    new_bytes = current + data_size

    if new_bytes <= @max_buffer_bytes do
      %{state | scroll_buffer: [state.scroll_buffer | data], scroll_buffer_bytes: new_bytes}
    else
      trim_scroll_buffer(state, data)
    end
  end

  defp trim_scroll_buffer(state, data) do
    full = IO.iodata_to_binary([state.scroll_buffer | data])
    full_size = byte_size(full)
    keep = min(full_size, @max_buffer_bytes)
    trimmed = binary_part(full, full_size - keep, keep)
    %{state | scroll_buffer: [trimmed], scroll_buffer_bytes: byte_size(trimmed)}
  end
end
