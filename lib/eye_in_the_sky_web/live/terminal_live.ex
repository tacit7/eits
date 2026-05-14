defmodule EyeInTheSkyWeb.TerminalLive do
  @moduledoc """
  Full-screen terminal LiveView backed by a persistent PTY process.

  The PTY session outlives this LiveView. Navigate away and come back — the
  process is still running. The scroll buffer is replayed into xterm.js on
  re-mount so the user sees history.

  ## Session key

  The PTY is keyed by `pty_session_key` from the LiveView session map.
  Pass a stable key (e.g., a user or session UUID) to share the same PTY
  across reconnects and navigation. Falls back to a per-mount unique key.

  ## Input/output flow

  - User types → JS hook pushes `pty_input` → handle_event writes to PtyServer
  - PtyServer output → sends `{:pty_output, data}` to this LiveView pid
  - handle_info forwards to client via `push_event("pty_output", %{data: base64})`
  - Resize → JS hook pushes `pty_resize` → handle_event calls PtyServer.resize/3
  - On subscribe → PtyServer sends `{:pty_scroll_buffer, binary}` → replayed as pty_output
  """

  use EyeInTheSkyWeb, :live_view

  require Logger

  alias EyeInTheSky.Terminal.{PtyServer, PtySupervisor}
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      session_key = Map.get(session, "pty_session_key", generate_key())

      {:ok, pty_pid} =
        PtySupervisor.find_or_start_pty(session_key: session_key, cols: 220, rows: 50)

      # subscribe/1 immediately sends {:pty_scroll_buffer, binary} with accumulated history
      :ok = PtyServer.subscribe(pty_pid)

      {:ok,
       socket
       |> assign(:pty_pid, pty_pid)
       |> assign(:session_key, session_key)
       |> assign(:page_title, "Terminal")}
    else
      {:ok, assign(socket, pty_pid: nil, session_key: nil, page_title: "Terminal")}
    end
  end

  @impl true
  def terminate(_reason, %{assigns: %{pty_pid: pid}}) when is_pid(pid) do
    # Unsubscribe only — do NOT stop the PtyServer. The OS process keeps running.
    PtyServer.unsubscribe(pid)
  end

  def terminate(_reason, _socket), do: :ok

  @impl true
  def handle_event("pty_input", %{"data" => data}, socket) do
    if pid = socket.assigns.pty_pid do
      PtyServer.write(pid, data)
    end

    {:noreply, socket}
  end

  def handle_event("pty_resize", %{"cols" => cols, "rows" => rows}, socket) do
    if pid = socket.assigns.pty_pid do
      PtyServer.resize(pid, cols, rows)
    end

    {:noreply, socket}
  end

  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  def handle_event(event, _params, socket) do
    Logger.debug("TerminalLive: unexpected handle_event: #{event}")
    {:noreply, socket}
  end

  @impl true
  # Scroll buffer replay on (re-)subscribe — write into xterm.js as if it were live output
  def handle_info({:pty_scroll_buffer, buffer}, socket) when byte_size(buffer) > 0 do
    {:noreply, push_event(socket, "pty_output", %{data: Base.encode64(buffer)})}
  end

  def handle_info({:pty_scroll_buffer, _empty}, socket), do: {:noreply, socket}

  # Live output from PtyServer
  def handle_info({:pty_output, data}, socket) do
    {:noreply, push_event(socket, "pty_output", %{data: Base.encode64(data)})}
  end

  def handle_info(:pty_exited, socket) do
    {:noreply,
     socket
     |> assign(:pty_pid, nil)
     |> push_event("pty_output", %{data: Base.encode64("\r\n[process exited]\r\n")})}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[100dvh] bg-zinc-950">
      <div class="flex items-center gap-2 px-4 py-2 bg-zinc-900 border-b border-zinc-800 shrink-0">
        <.icon name="hero-command-line" class="w-4 h-4 text-zinc-400" />
        <span class="text-sm font-medium text-zinc-300">Terminal</span>
        <span class="ml-auto text-xs text-zinc-600">bash</span>
      </div>
      <div
        id="terminal-container"
        phx-hook="PtyHook"
        phx-update="ignore"
        class="flex-1 min-h-0 p-2"
      >
      </div>
    </div>
    """
  end

  # --- Private ---

  defp generate_key, do: "terminal-#{System.unique_integer([:positive])}"
end
