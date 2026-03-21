defmodule EyeInTheSkyWeb.DmLive.StreamState do
  @moduledoc """
  Streaming/real-time state event handlers extracted from DmLive.

  Handles all handle_info callbacks related to live stream content,
  tool events, and the prompt queue. All public functions return
  {:noreply, socket}.
  """

  import Phoenix.Component, only: [assign: 3]

  require Logger

  def handle_stream_delta(:text, text, socket) do
    new_content = socket.assigns.stream_content <> text

    Logger.info(
      "[DmLive] stream_delta text, total_len=#{String.length(new_content)}, show=#{socket.assigns.show_live_stream}"
    )

    {:noreply, assign(socket, :stream_content, new_content)}
  end

  def handle_stream_delta(:tool_use, name, socket) do
    Logger.info("[DmLive] stream_delta tool_use=#{name}, show=#{socket.assigns.show_live_stream}")
    {:noreply, assign(socket, :stream_tool, name)}
  end

  def handle_stream_delta(:thinking, _content, socket) do
    {:noreply, socket}
  end

  def handle_stream_delta(_type, _content, socket) do
    {:noreply, socket}
  end

  def handle_stream_replace(:text, text, socket) do
    Logger.info(
      "[DmLive] stream_replace text, len=#{String.length(text)}, show=#{socket.assigns.show_live_stream}"
    )

    {:noreply, assign(socket, :stream_content, text)}
  end

  def handle_stream_replace(:thinking, text, socket) do
    Logger.info("[DmLive] stream_replace thinking, len=#{String.length(text)}")
    {:noreply, assign(socket, :stream_thinking, text)}
  end

  def handle_stream_replace(_type, _content, socket) do
    {:noreply, socket}
  end

  def handle_stream_clear(socket) do
    Logger.info("[DmLive] stream_clear")

    socket =
      socket
      |> assign(:stream_content, "")
      |> assign(:stream_tool, nil)
      |> assign(:stream_thinking, nil)

    {:noreply, socket}
  end

  def handle_stream_tool_input(name, _input, socket) do
    Logger.info("[DmLive] stream_tool_input tool=#{name}")
    {:noreply, assign(socket, :stream_tool, name)}
  end

  def handle_tool_use(tool_name, socket) do
    {:noreply, assign(socket, :stream_tool, tool_name)}
  end

  def handle_queue_updated(prompts, socket) do
    {:noreply, assign(socket, :queued_prompts, prompts)}
  end
end
