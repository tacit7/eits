defmodule EyeInTheSkyWeb.Components.TerminalWindowComponent do
  @moduledoc """
  Draggable/resizable terminal window for the canvas page.

  Mirrors ChatWindowComponent's chrome (title bar, close button, drag/resize hooks)
  but renders an xterm.js PTY terminal instead of a message list.

  PTY lifecycle:
  - PtyServer is started by CanvasLive (the parent) with subscriber_tag: id,
    so output arrives at CanvasLive as {:pty_output, id, data}.
  - CanvasLive routes via send_update(TerminalWindowComponent, id: ..., pty_output: data).
  - update/2 calls push_event("pty_output_<id>", ...) to deliver to the JS hook.

  JS hook:
  - The container element carries phx-hook="TerminalHook" and data-terminal-id=id.
  - TerminalHook listens for "pty_output_<id>" events scoped to this component.
  - Input is pushed as "pty_input" and "pty_resize" events (handled here).
  """

  use EyeInTheSkyWeb, :live_component

  @impl true
  def update(%{pty_output: data} = assigns, socket) do
    # Route PTY output to the xterm.js hook using a component-scoped event name.
    # Use ct.id (integer) not component id string, so the JS dataset attribute matches.
    {:ok,
     socket
     |> assign(assigns)
     |> push_event("pty_output_#{socket.assigns.ct.id}", %{data: Base.encode64(data)})}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("pty_input", %{"data" => data}, socket) do
    if pid = socket.assigns[:pty_pid] do
      EyeInTheSky.Terminal.PtyServer.write(pid, data)
    end

    {:noreply, socket}
  end

  def handle_event("pty_resize", %{"cols" => cols, "rows" => rows}, socket) do
    if pid = socket.assigns[:pty_pid] do
      EyeInTheSky.Terminal.PtyServer.resize(pid, cols, rows)
    end

    {:noreply, socket}
  end

  def handle_event("close", _params, socket) do
    send(self(), {:remove_terminal_window, socket.assigns.ct.id})
    {:noreply, socket}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"terminal-window-#{@id}"}
      data-terminal-window
      data-terminal-id={@id}
      phx-hook="TerminalWindowHook"
      style={"position: absolute; left: #{@ct.pos_x}px; top: #{@ct.pos_y}px; width: #{@ct.width}px; height: #{@ct.height}px; resize: both; overflow: auto;"}
      class="bg-zinc-950 rounded-xl shadow-2xl border border-zinc-800 flex flex-col"
    >
      <%!-- Title bar — matches ChatWindowComponent chrome --%>
      <div
        data-drag-handle
        class="flex items-center justify-between px-3 py-2 bg-zinc-900 border-b border-zinc-800 rounded-t-xl cursor-move select-none shrink-0"
      >
        <div class="flex items-center gap-2">
          <.icon name="hero-command-line" class="size-3.5 text-zinc-400" />
          <span class="text-xs font-medium text-zinc-300">Terminal</span>
          <span class="text-xs text-zinc-600">bash</span>
        </div>
        <div class="flex items-center gap-1.5">
          <button
            type="button"
            phx-click="close"
            phx-target={@myself}
            class="size-3 rounded-full bg-error/70 hover:bg-error transition-colors shrink-0"
            title="Close terminal"
          />
        </div>
      </div>
      <%!-- xterm.js mount point --%>
      <div
        id={"terminal-pty-#{@ct.id}"}
        data-terminal-id={@ct.id}
        phx-hook="TerminalHook"
        phx-update="ignore"
        phx-target={@myself}
        class="flex-1 min-h-0 p-1"
      >
      </div>
    </div>
    """
  end
end
