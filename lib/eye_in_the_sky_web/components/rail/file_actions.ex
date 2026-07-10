defmodule EyeInTheSkyWeb.Components.Rail.FileActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias EyeInTheSky.Projects.FileTree
  alias EyeInTheSky.Settings
  alias EyeInTheSkyWeb.Components.Rail.Loader
  alias EyeInTheSkyWeb.Helpers.ViewHelpers

  def handle_file_open(%{"path" => path}, socket) do
    with %{path: root} when not is_nil(root) <- socket.assigns.sidebar_project,
         {:ok, %{content: content, language: language, hash: hash}} <-
           FileTree.read_file(root, path) do
      name = Path.basename(path)
      lang_str = to_string(language)

      existing = Enum.find(socket.assigns.file_tabs, &(&1.path == path))

      tabs =
        if existing do
          socket.assigns.file_tabs
        else
          socket.assigns.file_tabs ++
            [%{path: path, name: name, content: content, language: lang_str, hash: hash}]
        end

      was_empty = socket.assigns.file_tabs == []
      socket2 = socket |> assign(:file_tabs, tabs) |> assign(:active_tab_path, path)
      socket2 = if was_empty, do: push_event(socket2, "file-editor-open", %{}), else: socket2
      {:noreply, socket2}
    else
      {:error, :binary_file} ->
        {:noreply, put_flash(socket, :info, "Binary file — cannot open")}

      {:error, :file_too_large} ->
        {:noreply, put_flash(socket, :info, "File too large to open (over 1 MB)")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot open file")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_file_switch_tab(%{"path" => path}, socket) do
    {:noreply, assign(socket, :active_tab_path, path)}
  end

  def handle_file_close_tab(%{"path" => path}, socket) do
    tabs = Enum.reject(socket.assigns.file_tabs, &(&1.path == path))

    active =
      cond do
        tabs == [] ->
          nil

        socket.assigns.active_tab_path == path ->
          List.last(tabs).path

        true ->
          socket.assigns.active_tab_path
      end

    socket2 = socket |> assign(:file_tabs, tabs) |> assign(:active_tab_path, active)
    socket2 = if tabs == [], do: push_event(socket2, "file-editor-close", %{}), else: socket2
    {:noreply, socket2}
  end

  def handle_file_save(%{"path" => path, "content" => content, "original_hash" => hash}, socket) do
    with %{path: root} when not is_nil(root) <- socket.assigns.sidebar_project,
         {:ok, %{hash: new_hash}} <- FileTree.write_file(root, path, content, original_hash: hash) do
      tabs =
        Enum.map(socket.assigns.file_tabs, fn tab ->
          if tab.path == path,
            do: %{tab | content: content, hash: new_hash},
            else: tab
        end)

      {:noreply, assign(socket, :file_tabs, tabs)}
    else
      {:error, :conflict} ->
        {:noreply, put_flash(socket, :error, "Save conflict — file changed on disk")}

      {:error, :symlink_not_saveable} ->
        {:noreply, put_flash(socket, :error, "Cannot save symlinked files")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Save failed")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_file_expand(%{"path" => path}, socket) do
    with %{path: root} when not is_nil(root) <- socket.assigns.sidebar_project do
      expanded = MapSet.put(socket.assigns.flyout_file_expanded, path)
      children_cache = socket.assigns.flyout_file_children

      socket =
        if Map.has_key?(children_cache, path) do
          assign(socket, :flyout_file_expanded, expanded)
        else
          case FileTree.children(root, path) do
            {:ok, nodes} ->
              socket
              |> assign(:flyout_file_expanded, expanded)
              |> assign(:flyout_file_children, Map.put(children_cache, path, nodes))

            {:error, _} ->
              assign(socket, :flyout_file_expanded, expanded)
          end
        end

      {:noreply, persist_file_expanded(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_file_collapse(%{"path" => path}, socket) do
    expanded = MapSet.delete(socket.assigns.flyout_file_expanded, path)

    socket =
      socket
      |> assign(:flyout_file_expanded, expanded)
      |> persist_file_expanded()

    {:noreply, socket}
  end

  def handle_file_refresh(socket) do
    with %{path: root} when not is_nil(root) <- socket.assigns.sidebar_project do
      expanded = socket.assigns.flyout_file_expanded

      # Re-fetch children for every currently expanded path.
      # Prune any that fail (dir deleted or unreadable since last expand).
      refreshed_children =
        expanded
        |> Enum.reduce(%{}, fn path, acc ->
          case FileTree.children(root, path) do
            {:ok, nodes} -> Map.put(acc, path, nodes)
            {:error, _} -> acc
          end
        end)

      # Prune expanded set to only paths that successfully re-fetched.
      valid_expanded =
        expanded
        |> Enum.filter(&Map.has_key?(refreshed_children, &1))
        |> MapSet.new()

      socket =
        case FileTree.root(root) do
          {:ok, nodes} ->
            socket
            |> assign(:flyout_file_nodes, nodes)
            |> assign(:flyout_file_children, refreshed_children)
            |> assign(:flyout_file_expanded, valid_expanded)
            |> assign(:flyout_file_error, nil)

          {:error, reason} ->
            socket
            |> assign(:flyout_file_nodes, [])
            |> assign(:flyout_file_children, %{})
            |> assign(:flyout_file_expanded, MapSet.new())
            |> assign(:flyout_file_error, Loader.file_error_message(reason))
        end

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  @doc """
  Reveals a file or directory in the OS file manager. The Phoenix server
  always runs on the user's machine (dev server or the desktop app's
  embedded release), so a server-side `open -R` works for both web and
  desktop — same trust boundary as RailSessionActions.handle_open_worktree.
  """
  def handle_reveal_file(%{"path" => rel_path}, socket) do
    with %{path: root} when not is_nil(root) <- socket.assigns.sidebar_project,
         {:ok, abs_path} <- FileTree.resolve(root, rel_path) do
      reveal_path(abs_path)
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not reveal path")}
    end
  end

  defp reveal_path(path) do
    case :os.type() do
      {:unix, :darwin} -> System.cmd("open", ["-R", path])
      {:win32, _} -> System.cmd("explorer", ["/select,", path])
      _ -> System.cmd("xdg-open", [Path.dirname(path)])
    end
  end

  def handle_open_file_in_editor(%{"path" => rel_path}, socket) do
    with %{path: root} when not is_nil(root) <- socket.assigns.sidebar_project,
         {:ok, abs_path} <- FileTree.resolve(root, rel_path) do
      editor = Settings.get("preferred_editor") || "code"
      ViewHelpers.handle_open_in_editor(abs_path, editor, socket)
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not open file")}
    end
  end

  @doc """
  Renames a file on disk (regular files only — see FileTree.rename/3) and
  keeps any open editor tab in sync. Renaming a directory's open descendant
  tabs is NOT remapped — a save against a stale tab path will error rather
  than corrupt data, but the user needs to re-open the tab. Acceptable
  because rename here is deliberately scoped to files, not directories.
  """
  def handle_rename_file(%{"path" => rel_path, "name" => new_name}, socket) do
    with %{path: root} when not is_nil(root) <- socket.assigns.sidebar_project,
         {:ok, new_rel_path} <- FileTree.rename(root, rel_path, new_name) do
      tabs =
        Enum.map(socket.assigns.file_tabs, fn tab ->
          if tab.path == rel_path do
            %{tab | path: new_rel_path, name: Path.basename(new_rel_path)}
          else
            tab
          end
        end)

      active =
        if socket.assigns.active_tab_path == rel_path,
          do: new_rel_path,
          else: socket.assigns.active_tab_path

      socket
      |> assign(:file_tabs, tabs)
      |> assign(:active_tab_path, active)
      |> handle_file_refresh()
    else
      {:error, :target_exists} ->
        {:noreply, put_flash(socket, :error, "A file with that name already exists")}

      {:error, :invalid_name} ->
        {:noreply, put_flash(socket, :error, "Invalid file name")}

      {:error, :unsupported_file_type} ->
        {:noreply, put_flash(socket, :error, "Only files can be renamed")}

      _ ->
        {:noreply, put_flash(socket, :error, "Rename failed")}
    end
  end

  # Emits a save_rail_state patch with the current expanded path list.
  # Called after any expand/collapse mutation so localStorage stays in sync.
  defp persist_file_expanded(socket) do
    paths = socket.assigns.flyout_file_expanded |> MapSet.to_list()
    push_event(socket, "save_rail_state", %{file_expanded: paths})
  end
end
