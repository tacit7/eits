defmodule EyeInTheSky.Editors do
  @moduledoc """
  Registry of known external editors with detection and async launch.

  `detect_installed/0` returns the subset of editors found on this machine.
  Detection checks extra PATH directories before the process PATH — important
  because a Phoenix server launched as a macOS GUI app (launchd, nohup, etc.)
  may not inherit the user's shell PATH and could be missing /opt/homebrew/bin.

  `open/2` launches using the resolved binary path captured at detection time,
  not by re-searching PATH at launch time.
  """

  @editors [
    %{id: "code", label: "VS Code", bin: "code"},
    %{id: "cursor", label: "Cursor", bin: "cursor"},
    %{id: "zed", label: "Zed", bin: "zed"},
    %{id: "nvim", label: "Neovim", bin: "nvim"},
    %{id: "vim", label: "Vim", bin: "vim"},
    %{id: "hx", label: "Helix", bin: "hx"},
    %{id: "subl", label: "Sublime Text", bin: "subl"},
    %{id: "emacs", label: "Emacs", bin: "emacs"},
    %{id: "nano", label: "nano", bin: "nano"}
  ]

  # Paths allowed to be opened in an external editor.
  @allowed_roots [
    Path.expand("~/.claude"),
    Path.expand("~/projects")
  ]

  # Extra directories to probe before the process PATH — macOS GUI processes
  # often don't inherit Homebrew or user-local bin dirs.
  @extra_path_dirs [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/local/sbin"
  ]

  @doc "All editor IDs in registry order."
  def all_ids, do: Enum.map(@editors, & &1.id)

  @doc "All editor entries (id, label, bin)."
  def all, do: @editors

  @doc """
  Returns the subset of editors found on this machine, each enriched with
  a `:cmd` field holding the resolved binary path (or macOS open invocation).

  List is in registry order. Call once at mount; cache in assigns.
  """
  def detect_installed do
    dirs = build_search_dirs()

    @editors
    |> Enum.flat_map(fn ed ->
      case resolve(ed, dirs) do
        nil -> []
        cmd -> [Map.put(ed, :cmd, cmd)]
      end
    end)
  end

  @doc """
  Find an editor struct by id. Returns `nil` if unknown.
  Does NOT check whether the editor is installed — use detect_installed/0 for that.
  """
  def find(id), do: Enum.find(@editors, &(&1.id == id))

  @doc """
  Open `path` in the editor identified by `editor_id`.

  Resolves the binary at call time (so a fresh install is picked up without
  waiting for a server restart). Returns `{:ok, label}` on success or
  `{:error, reason}` on validation failure.
  """
  def open(editor_id, path) when is_binary(editor_id) and is_binary(path) do
    dirs = build_search_dirs()

    with {:ok, %{label: label} = ed} <- fetch_editor(editor_id),
         {:ok, cmd} <- fetch_cmd(ed, dirs),
         :ok <- check_allowed(path),
         :ok <- check_exists(path) do
      launch(cmd, path)
      {:ok, label}
    end
  end

  # --- Private ---

  defp fetch_editor(editor_id) do
    case find(editor_id) do
      nil -> {:error, :unknown_editor}
      ed -> {:ok, ed}
    end
  end

  defp fetch_cmd(ed, dirs) do
    case resolve(ed, dirs) do
      nil -> {:error, :not_installed}
      cmd -> {:ok, cmd}
    end
  end

  defp check_allowed(path) do
    if path_allowed?(path), do: :ok, else: {:error, :not_allowed}
  end

  defp check_exists(path) do
    if File.exists?(path), do: :ok, else: {:error, :not_found}
  end

  # Build the list of directories to search, extra dirs first so they win
  # over whatever the process inherited as PATH.
  defp build_search_dirs do
    home = System.get_env("HOME", "")

    extra =
      [@extra_path_dirs, [Path.join(home, ".local/bin")]]
      |> List.flatten()

    from_path =
      case System.get_env("PATH") do
        nil -> []
        path_str -> String.split(path_str, ":")
      end

    (extra ++ from_path)
    |> Enum.uniq()
    |> Enum.filter(&File.dir?/1)
  end

  # Try binary search first, then macOS app bundle fallback.
  defp resolve(%{bin: bin} = ed, dirs) do
    find_binary(bin, dirs) || mac_app_cmd(ed)
  end

  # Walk dirs looking for an executable named `bin`.
  defp find_binary(bin, dirs) do
    Enum.find_value(dirs, fn dir ->
      candidate = Path.join(dir, bin)

      if File.regular?(candidate) && executable?(candidate) do
        candidate
      end
    end)
  end

  # On macOS: check /Applications and ~/Applications for a known .app bundle.
  # Returns the `open -a <AppName>` command string if found, else nil.
  defp mac_app_cmd(%{bin: bin}) do
    case :os.type() do
      {:unix, :darwin} ->
        home = System.get_env("HOME", "")
        roots = ["/Applications", Path.join(home, "Applications")]
        names = mac_app_names(bin)
        find_bundle(roots, names)

      _ ->
        nil
    end
  end

  defp find_bundle(roots, names) do
    Enum.find_value(roots, fn root ->
      Enum.find_value(names, fn name ->
        bundle = Path.join(root, "#{name}.app")
        if File.exists?(bundle), do: "__open_a__:#{name}", else: nil
      end)
    end)
  end

  defp launch("__open_a__:" <> app_name, path) do
    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      System.cmd("open", ["-a", app_name, path], stderr_to_stdout: true)
    end)
  end

  defp launch(cmd, path) do
    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      System.cmd(cmd, [path], stderr_to_stdout: true, cd: "/")
    end)
  end

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _ -> false
    end
  end

  defp mac_app_names("code"), do: ["Visual Studio Code"]
  defp mac_app_names("cursor"), do: ["Cursor"]
  defp mac_app_names("zed"), do: ["Zed"]
  defp mac_app_names("subl"), do: ["Sublime Text"]
  defp mac_app_names("emacs"), do: ["Emacs"]
  defp mac_app_names(_), do: []

  defp path_allowed?(path) do
    expanded = Path.expand(path)
    Enum.any?(@allowed_roots, &String.starts_with?(expanded, &1 <> "/"))
  end
end
