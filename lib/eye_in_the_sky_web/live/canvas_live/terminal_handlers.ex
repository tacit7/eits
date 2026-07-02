defmodule EyeInTheSkyWeb.CanvasLive.TerminalHandlers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [send_update: 2]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Canvases
  alias EyeInTheSky.Terminal.PtyServer
  alias EyeInTheSky.Terminal.PtySupervisor
  alias EyeInTheSkyWeb.Components.TerminalWindowComponent

  def handle_add_terminal(socket) do
    canvas_id = socket.assigns.active_canvas_id

    if is_nil(canvas_id) do
      {:noreply, socket}
    else
      offset = length(socket.assigns.canvas_sessions) + length(socket.assigns.canvas_terminals)

      attrs = %{
        pos_x: 24 + offset * 32,
        pos_y: 24 + offset * 32,
        width: 620,
        height: 400
      }

      case Canvases.create_terminal(canvas_id, attrs) do
        {:ok, ct} ->
          {:ok, pty_pid} =
            PtySupervisor.find_or_start_pty(session_key: "canvas-terminal-#{ct.id}")

          PtyServer.subscribe(pty_pid, self(), ct.id)

          {:noreply,
           socket
           |> assign(:canvas_terminals, socket.assigns.canvas_terminals ++ [ct])
           |> assign(:terminal_pty_map, Map.put(socket.assigns.terminal_pty_map, ct.id, pty_pid))}

        {:error, _} ->
          {:noreply, socket}
      end
    end
  end

  def handle_terminal_moved(id_str, x, y, socket) do
    if id = parse_int(id_str), do: Canvases.update_terminal_layout(id, %{pos_x: x, pos_y: y})
    {:noreply, socket}
  end

  def handle_terminal_resized(id_str, w, h, socket) do
    if id = parse_int(id_str), do: Canvases.update_terminal_layout(id, %{width: w, height: h})
    {:noreply, socket}
  end

  def handle_pty_scroll_buffer(terminal_id, data, socket) do
    send_update(TerminalWindowComponent,
      id: "terminal-window-#{terminal_id}",
      pty_output: data
    )

    {:noreply, socket}
  end

  def handle_pty_output(terminal_id, data, socket) do
    send_update(TerminalWindowComponent,
      id: "terminal-window-#{terminal_id}",
      pty_output: data
    )

    {:noreply, socket}
  end

  def handle_pty_exited(terminal_id, socket) do
    {:noreply, remove_terminal(socket, terminal_id)}
  end

  def handle_remove_terminal_window(terminal_id, socket) do
    if pid = socket.assigns.terminal_pty_map[terminal_id] do
      PtyServer.stop(pid)
    end

    Canvases.delete_terminal(terminal_id)
    {:noreply, remove_terminal(socket, terminal_id)}
  end

  defp remove_terminal(socket, terminal_id) do
    socket
    |> assign(
      :canvas_terminals,
      Enum.reject(socket.assigns.canvas_terminals, &(&1.id == terminal_id))
    )
    |> assign(:terminal_pty_map, Map.delete(socket.assigns.terminal_pty_map, terminal_id))
  end
end
