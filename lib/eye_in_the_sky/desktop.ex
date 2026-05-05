defmodule EyeInTheSky.Desktop do
  @moduledoc """
  Desktop app integration via ElixirKit PubSub.
  All functions are no-ops when not running in desktop mode (standard web).
  """

  @doc """
  Send a native macOS notification.

  Pass an optional `path` to navigate the desktop window when the user
  clicks the notification (e.g. `"/dm/abc-123"`). Without a path the
  notification still shows but clicking only brings the window to focus.
  """
  def notify(title, body, path \\ nil) do
    msg =
      if path,
        do: "notify:#{title}|#{body}|#{path}",
        else: "notify:#{title}|#{body}"

    broadcast(msg)
  end

  @doc "Set the dock badge count. Pass 0 to clear."
  def set_badge(count) when is_integer(count) and count >= 0 do
    broadcast("badge:#{count}")
  end

  @doc "Clear the dock badge."
  def clear_badge, do: set_badge(0)

  @doc "Copy text to the system clipboard."
  def copy_to_clipboard(text) when is_binary(text) do
    broadcast("clipboard:#{text}")
  end

  @doc "Open a native save-file dialog with the given filename and content."
  def save_file(filename, content) when is_binary(filename) and is_binary(content) do
    broadcast("save-file:#{filename}|#{content}")
  end

  @doc "Navigate the desktop webview to a path (e.g., '/sessions')."
  def navigate(path) when is_binary(path) do
    broadcast("navigate:#{path}")
  end

  @doc "Returns true when running inside the Tauri desktop shell."
  def desktop_mode? do
    is_pid(Process.whereis(ElixirKit.PubSub))
  end

  defp broadcast(message) do
    if desktop_mode?() do
      ElixirKit.PubSub.broadcast("messages", message)
    end

    :ok
  end
end
