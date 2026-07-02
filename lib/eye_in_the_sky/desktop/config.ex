defmodule EyeInTheSky.Desktop.Config do
  @moduledoc """
  Pre-boot configuration file for the Tauri desktop app.

  The Tauri shell reads `$XDG_CONFIG_HOME/eits/desktop.json` (default
  `~/.config/eits/desktop.json`) *before* booting the embedded Phoenix
  release — settings that must be known pre-boot (like the HTTP port)
  cannot live in the Postgres-backed settings table. This module is the
  Phoenix-side reader/writer for that file; the Rust side
  (`src-tauri/src/lib.rs`, `desktop_config_port/0`) is the pre-boot
  consumer.

  Changes take effect on the next desktop app launch.
  """

  # Keep in sync with DEFAULT_PORT in src-tauri/src/lib.rs.
  @default_port 34877
  @port_range 1024..49151

  @doc "Default embedded-server port (mirrors src-tauri DEFAULT_PORT)."
  def default_port, do: @default_port

  @doc "Valid port range: above privileged, below the OS ephemeral range."
  def port_range, do: @port_range

  @doc "Path to the desktop config file, honoring XDG_CONFIG_HOME."
  def config_path do
    base = System.get_env("XDG_CONFIG_HOME") || Path.expand("~/.config")
    Path.join([base, "eits", "desktop.json"])
  end

  @doc "Read the desktop config; returns %{} when missing or malformed."
  def read_config do
    with {:ok, raw} <- File.read(config_path()),
         {:ok, map} when is_map(map) <- Jason.decode(raw) do
      map
    else
      _ -> %{}
    end
  end

  @doc "The configured port, or nil when unset/invalid."
  def configured_port do
    case read_config() do
      %{"port" => port} when is_integer(port) ->
        if port in @port_range, do: port, else: nil

      _ ->
        nil
    end
  end

  @doc """
  Persist the desktop port. Merges into the existing config file so other
  keys survive. Returns :ok or {:error, reason}.
  """
  def write_port(port) when is_integer(port) do
    if port in @port_range do
      path = config_path()

      with :ok <- File.mkdir_p(Path.dirname(path)),
           config = Map.put(read_config(), "port", port),
           :ok <- File.write(path, Jason.encode!(config, pretty: true)) do
        :ok
      end
    else
      {:error, :out_of_range}
    end
  end

  def write_port(_), do: {:error, :invalid}

  @doc """
  Whether the user has granted global Claude Code hooks + skills install.
  Mirrors `hooks_consent/0` in `src-tauri/src/lib.rs` — both sides read/write
  the same `"hooks_consent"` key ("granted" | "denied") in this file.

  Returns `nil` when never asked (first launch hasn't run the consent dialog
  yet — the Rust side owns that; this module is read/write-only for it).
  """
  def hooks_consent do
    case read_config() do
      %{"hooks_consent" => "granted"} -> true
      %{"hooks_consent" => "denied"} -> false
      _ -> nil
    end
  end

  @doc """
  Change the hooks/skills consent decision from within the app (Settings →
  Desktop). Takes effect on next launch — the Rust installer only runs in
  `setup()`, before Elixir boots. Returns :ok or {:error, reason}.
  """
  def write_hooks_consent(granted?) when is_boolean(granted?) do
    path = config_path()
    value = if granted?, do: "granted", else: "denied"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         config = Map.put(read_config(), "hooks_consent", value),
         :ok <- File.write(path, Jason.encode!(config, pretty: true)) do
      :ok
    end
  end
end
