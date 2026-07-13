defmodule EyeInTheSky.Terminals do
  @moduledoc """
  Registry of known terminal emulators with detection and command launch.

  `detect_installed/0` returns the subset of terminals found on this machine.
  `open/3` launches a shell command in the specified terminal, optionally
  starting in a given working directory.

  Detection checks .app bundles (macOS) before PATH binaries so GUI terminals
  like iTerm2 are found even when their CLI shim is not on PATH.
  """

  # id    — settings key value
  # label — display name
  # mac_app — .app bundle name on macOS (nil if not a mac .app)
  # bin     — CLI binary name (nil if app-only)
  @terminals [
    %{id: "iterm2", label: "iTerm2", mac_app: "iTerm", bin: nil},
    %{id: "terminal", label: "Terminal", mac_app: "Terminal", bin: nil},
    %{id: "ghostty", label: "Ghostty", mac_app: "Ghostty", bin: "ghostty"},
    %{id: "warp", label: "Warp", mac_app: "Warp", bin: nil},
    %{id: "kitty", label: "Kitty", mac_app: nil, bin: "kitty"},
    %{id: "alacritty", label: "Alacritty", mac_app: nil, bin: "alacritty"}
  ]

  @extra_path_dirs ["/opt/homebrew/bin", "/usr/local/bin"]

  # --- Public API ---

  @doc "All terminal entries (id, label)."
  def all, do: @terminals

  @doc "Find a terminal struct by id. Returns nil if unknown."
  def find(id), do: Enum.find(@terminals, &(&1.id == id))

  @doc """
  Returns the subset of terminals found on this machine.
  Checks .app bundles first (macOS), then PATH binaries.
  """
  def detect_installed do
    home = System.get_env("HOME", "")
    app_roots = ["/Applications", Path.join(home, "Applications")]
    bin_dirs = build_bin_dirs()

    Enum.filter(@terminals, fn t ->
      app_detected?(t, app_roots) || bin_detected?(t, bin_dirs)
    end)
  end

  @doc """
  Launch `command` (a shell string) in the terminal identified by `terminal_id`,
  starting in `dir`. Returns :ok or {:error, reason}.
  """
  def open(terminal_id, command, dir \\ "~") do
    case find(terminal_id) do
      nil -> {:error, :unknown_terminal}
      t -> launch(t, command, dir)
    end
  end

  # --- Detection helpers ---

  defp app_detected?(%{mac_app: nil}, _roots), do: false

  defp app_detected?(%{mac_app: app}, roots) do
    case :os.type() do
      {:unix, :darwin} -> Enum.any?(roots, &File.exists?(Path.join(&1, "#{app}.app")))
      _ -> false
    end
  end

  defp bin_detected?(%{bin: nil}, _dirs), do: false

  defp bin_detected?(%{bin: bin}, dirs) do
    Enum.any?(dirs, fn dir ->
      candidate = Path.join(dir, bin)
      File.regular?(candidate) && executable?(candidate)
    end)
  end

  defp build_bin_dirs do
    from_path =
      case System.get_env("PATH") do
        nil -> []
        s -> String.split(s, ":")
      end

    (@extra_path_dirs ++ from_path)
    |> Enum.uniq()
    |> Enum.filter(&File.dir?/1)
  end

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _ -> false
    end
  end

  # --- Launch strategies ---

  # iTerm2: AppleScript — most reliable on macOS
  defp launch(%{id: "iterm2"}, command, dir) do
    safe_cmd = applescript_escape("cd #{shell_escape(dir)} && #{command}")

    script = """
    tell application "iTerm"
      activate
      set newWindow to (create window with default profile)
      tell current session of newWindow
        write text "#{safe_cmd}"
      end tell
    end tell
    """

    run_applescript(script)
  end

  # Terminal.app: AppleScript
  defp launch(%{id: "terminal"}, command, dir) do
    safe_cmd = applescript_escape("cd #{shell_escape(dir)} && #{command}")

    script = """
    tell application "Terminal"
      activate
      do script "#{safe_cmd}"
    end tell
    """

    run_applescript(script)
  end

  # Warp: URI scheme — opens a new tab at dir and runs command
  defp launch(%{id: "warp"}, command, dir) do
    expanded = Path.expand(dir)
    uri = "warp://action/new_tab?path=#{URI.encode(expanded)}&cmd=#{URI.encode(command)}"

    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      System.cmd("open", [uri], stderr_to_stdout: true)
    end)

    :ok
  end

  # Kitty: positional args, no -e flag
  defp launch(%{id: "kitty", bin: bin}, command, dir) when is_binary(bin) do
    full_cmd = "cd #{shell_escape(Path.expand(dir))} && #{command}"

    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      System.cmd(bin, ["--", "sh", "-c", full_cmd], stderr_to_stdout: true)
    end)

    :ok
  end

  # Generic -e flag (Ghostty, Alacritty, others)
  defp launch(%{bin: bin}, command, dir) when is_binary(bin) do
    full_cmd = "cd #{shell_escape(Path.expand(dir))} && #{command}"

    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      System.cmd(bin, ["-e", "sh", "-c", full_cmd], stderr_to_stdout: true)
    end)

    :ok
  end

  defp launch(_, _, _), do: {:error, :unsupported_terminal}

  defp run_applescript(script) do
    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      System.cmd("osascript", ["-e", script], stderr_to_stdout: true)
    end)

    :ok
  end

  # Escape a string for embedding inside an AppleScript double-quoted string.
  defp applescript_escape(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  # POSIX single-quote escaping for shell arguments.
  defp shell_escape(str) do
    "'" <> String.replace(str, "'", "'\\''") <> "'"
  end
end
