defmodule EyeInTheSkyWeb.Helpers.SystemHelpers do
  @moduledoc """
  Helpers for interacting with the host operating system.
  """

  @doc """
  Open a file with the system's default application (cross-platform).
  """
  def open_in_system(path) when is_binary(path) do
    cmd =
      case :os.type() do
        {:unix, :darwin} -> "open"
        {:unix, _} -> "xdg-open"
        {:win32, _} -> "cmd"
      end

    args =
      case :os.type() do
        {:win32, _} -> ["/c", "start", "", path]
        _ -> [path]
      end

    System.cmd(cmd, args, stderr_to_stdout: true)
  end
end
