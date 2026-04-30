defmodule EyeInTheSky.Terminal.PtyServer do
  @moduledoc """
  GenServer that owns a single PTY session via erlexec.

  Lifecycle:
  - Started dynamically by PtySupervisor, one per terminal LiveView session.
  - Output from the PTY is forwarded to `subscriber` (a LiveView pid) via
    `{:pty_output, data}` messages.
  - The process exits (and takes the OS child with it) when the LiveView
    disconnects or `stop/1` is called.
  """

  use GenServer, restart: :temporary

  require Logger

  @default_cols 220
  @default_rows 50
  @shell System.find_executable("bash") || "/bin/bash"

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

    env = [
      {"TERM", "xterm-256color"},
      {"LANG", "en_US.UTF-8"},
      {"HOME", System.get_env("HOME", "/tmp")}
    ]

    opts = [
      {:stdout, self()},
      {:stderr, :stdout},
      :pty,
      {:env, env},
      :monitor
    ]

    case :exec.run(@shell, opts) do
      {:ok, _pid, os_pid} ->
        # Set initial window size after spawn — winsz is not a valid exec:run option
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

  # Process exited
  def handle_info({:DOWN, _ref, :process, _pid, {:exit_status, _code}}, state) do
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
