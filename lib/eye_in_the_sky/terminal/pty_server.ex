defmodule EyeInTheSky.Terminal.PtyServer do
  @moduledoc """
  GenServer that owns a single PTY session via erlexec.

  Lifecycle:
  - Started dynamically by PtySupervisor, one per terminal LiveView session.
  - Output from the PTY is forwarded to `subscriber` (a LiveView pid) via
    `{:pty_output, data}` messages.
  - The process exits (and takes the OS child with it) when the LiveView
    disconnects or `stop/1` is called.

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
  @shell_bin System.find_executable("bash") || "/bin/bash"

  # --- Public API ---

  def start_link(opts) do
    subscriber = Keyword.fetch!(opts, :subscriber)
    cols = Keyword.get(opts, :cols, @default_cols)
    rows = Keyword.get(opts, :rows, @default_rows)
    GenServer.start_link(__MODULE__, {subscriber, cols, rows})
  end

  @doc "Write data (keystrokes / paste) into the PTY."
  def write(pid, data), do: GenServer.cast(pid, {:write, data})

  @doc "Resize the PTY window."
  def resize(pid, cols, rows), do: GenServer.cast(pid, {:resize, cols, rows})

  @doc "Terminate the PTY and the GenServer."
  def stop(pid), do: GenServer.stop(pid, :normal)

  # --- Callbacks ---

  @impl true
  def init({subscriber, cols, rows}) do
    # Monitor the LiveView so we clean up when it dies.
    Process.monitor(subscriber)

    home = System.get_env("HOME", "/tmp")

    env = [
      {"TERM", "xterm-256color"},
      {"LANG", "en_US.UTF-8"},
      {"HOME", home},
      {"PATH", System.get_env("PATH", "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")},
      {"SHELL", @shell_bin},
      {"USER", System.get_env("USER", "user")},
      {"LOGNAME", System.get_env("LOGNAME", System.get_env("USER", "user"))}
    ]

    # List form → direct exec (no sh -c wrapping).
    # --norc --noprofile: skip init files that might exit early.
    # -i: force interactive mode so bash shows a prompt and reads stdin.
    shell_cmd = [@shell_bin, "--norc", "--noprofile", "-i"]

    opts = [
      # CRITICAL: without this erlexec defaults stdin to /dev/null
      :stdin,
      # deliver PTY output as {:stdout, os_pid, data}
      {:stdout, self()},
      # merge stderr into stdout stream
      {:stderr, :stdout},
      :pty,
      :pty_echo,
      {:env, env},
      :monitor
    ]

    case :exec.run(shell_cmd, opts) do
      {:ok, _erlang_pid, os_pid} ->
        # Set initial window size — winsz is not a valid exec:run option
        :exec.winsz(os_pid, rows, cols)
        {:ok, %{subscriber: subscriber, os_pid: os_pid, cols: cols, rows: rows}}

      {:error, reason} ->
        Logger.error("PtyServer: failed to spawn shell: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:write, data}, %{os_pid: os_pid} = state) do
    :exec.send(os_pid, data)
    {:noreply, state}
  end

  def handle_cast({:resize, cols, rows}, %{os_pid: os_pid} = state) do
    :exec.winsz(os_pid, rows, cols)
    {:noreply, %{state | cols: cols, rows: rows}}
  end

  @impl true
  # PTY output from erlexec
  def handle_info({:stdout, _os_pid, data}, %{subscriber: sub} = state) do
    send(sub, {:pty_output, data})
    {:noreply, state}
  end

  # erlexec: OS process exited with non-zero status
  def handle_info({:DOWN, _ref, :process, _pid, {:exit_status, _code}}, state) do
    send(state.subscriber, :pty_exited)
    {:stop, :normal, state}
  end

  # erlexec: OS process exited cleanly (exit code 0 → :normal via erlexec's ospid_loop)
  def handle_info({:DOWN, os_pid, :process, _lwp, :normal}, %{os_pid: os_pid} = state) do
    send(state.subscriber, :pty_exited)
    {:stop, :normal, state}
  end

  # LiveView died — clean up
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{subscriber: pid} = state) do
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{os_pid: os_pid}) do
    :exec.stop(os_pid)
  rescue
    _ -> :ok
  end
end
