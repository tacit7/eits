defmodule EyeInTheSkyWeb.Helpers.SystemHelpers do
  @moduledoc """
  Helpers for interacting with the host operating system.
  """

  @doc """
  Open a file in VS Code using the `code` CLI.
  Tries /usr/local/bin/code first (standard macOS shell-integration path),
  then falls back to whatever `code` resolves to in PATH.
  """
  def open_in_vscode(path) when is_binary(path) do
    code_cmd =
      if File.exists?("/usr/local/bin/code"),
        do: "/usr/local/bin/code",
        else: System.find_executable("code") || "/usr/local/bin/code"

    System.cmd(code_cmd, [path], stderr_to_stdout: true, cd: "/")
  end

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
