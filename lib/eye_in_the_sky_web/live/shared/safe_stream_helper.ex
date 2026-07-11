defmodule EyeInTheSkyWeb.Live.Shared.SafeStreamHelper do
  @moduledoc false
  import Phoenix.LiveView, only: [stream: 4]

  @doc """
  Wraps Phoenix.LiveView.stream/4, returning socket unchanged if lifecycle
  infrastructure is missing (unit test mock sockets lack live_temp.lifecycle).
  """
  def safe_stream(socket, name, items, opts) do
    stream(socket, name, items, opts)
  rescue
    KeyError -> socket
  end
end
