defmodule EyeInTheSkyWeb.TerminalLive do
  @moduledoc """
  Full-screen terminal LiveView backed by a PTY process.

  The xterm.js hook on the client handles rendering. Input/output flow:
  - User types → JS hook pushes `pty_input` event → handle_event writes to PtyServer
  - PtyServer receives output → sends `{:pty_output, data}` to this LiveView pid
  - handle_info forwards data to client via `push_event("pty_output", %{data: ...})`
  - Resize: JS hook pushes `pty_resize` on terminal resize → handle_event calls PtyServer.resize/3
  """

  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Terminal.{PtyServer, PtySupervisor}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok, pty_pid} =
        PtySupervisor.start_pty(subscriber: self(), cols: 220, rows: 50)

      {:ok,
       socket
       |> assign(:pty_pid, pty_pid)
       |> assign(:page_title, "Terminal")}
    else
      {:ok, assign(socket, pty_pid: nil, page_title: "Terminal")}
    end
  end

  @impl true
  def terminate(_reason, %{assigns: %{pty_pid: pid}}) when is_pid(pid) do
    PtyServer.stop(pid)
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

  @impl true
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
end
