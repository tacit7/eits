defmodule EyeInTheSkyWeb.Live.Shared.DmStreamHelpers do
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.DmLive.StreamState

  @reload_debounce_ms 300

  def handle_stream_delta(type, content, socket),
    do: StreamState.handle_stream_delta(type, content, socket)

  def handle_stream_replace(type, content, socket),
    do: StreamState.handle_stream_replace(type, content, socket)

  def handle_stream_clear(socket),
    do: StreamState.handle_stream_clear(socket)

  def handle_stream_tool_input(name, input, socket),
    do: StreamState.handle_stream_tool_input(name, input, socket)

  def handle_tool_use(tool_name, socket),
    do: StreamState.handle_tool_use(tool_name, socket)

  def handle_tool_result(socket) do
    socket = assign(socket, :stream_tool, nil)

    if socket.assigns.reload_timer do
      Process.cancel_timer(socket.assigns.reload_timer)
    end

    timer = Process.send_after(self(), :do_message_reload, @reload_debounce_ms)
    {:noreply, assign(socket, :reload_timer, timer)}
  end

  def handle_queue_updated(prompts, socket),
    do: StreamState.handle_queue_updated(prompts, socket)
end
