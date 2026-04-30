defmodule EyeInTheSkyWeb.Components.Rail.FileActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias EyeInTheSky.Projects.FileTree
  alias EyeInTheSkyWeb.Components.Rail.Loader

  def handle_file_open(%{"path" => path}, socket) do
    project = socket.assigns.sidebar_project

    if project && project.path do
      case FileTree.read_file(project.path, path) do
        {:ok, %{content: content, language: language, hash: hash}} ->
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

        {:error, :binary_file} ->
          {:noreply, put_flash(socket, :info, "Binary file — cannot open")}

        {:error, :file_too_large} ->
          {:noreply, put_flash(socket, :info, "File too large to open (over 1 MB)")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Cannot open file")}
      end
    else
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
    project = socket.assigns.sidebar_project

    if project && project.path do
      case FileTree.write_file(project.path, path, content, original_hash: hash) do
        {:ok, %{hash: new_hash}} ->
          tabs =
            Enum.map(socket.assigns.file_tabs, fn tab ->
              if tab.path == path,
                do: %{tab | content: content, hash: new_hash},
                else: tab
            end)

          {:noreply, assign(socket, :file_tabs, tabs)}

        {:error, :conflict} ->
          {:noreply, put_flash(socket, :error, "Save conflict — file changed on disk")}

        {:error, :symlink_not_saveable} ->
          {:noreply, put_flash(socket, :error, "Cannot save symlinked files")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Save failed")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_file_expand(%{"path" => path}, socket) do
    project = socket.assigns.sidebar_project

    if project && project.path do
      expanded = MapSet.put(socket.assigns.flyout_file_expanded, path)
      children_cache = socket.assigns.flyout_file_children

      socket =
        if Map.has_key?(children_cache, path) do
          assign(socket, :flyout_file_expanded, expanded)
        else
          case FileTree.children(project.path, path) do
            {:ok, nodes} ->
              socket
              |> assign(:flyout_file_expanded, expanded)
              |> assign(:flyout_file_children, Map.put(children_cache, path, nodes))

            {:error, _} ->
              assign(socket, :flyout_file_expanded, expanded)
          end
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_file_collapse(%{"path" => path}, socket) do
    expanded = MapSet.delete(socket.assigns.flyout_file_expanded, path)
    {:noreply, assign(socket, :flyout_file_expanded, expanded)}
  end

  def handle_file_refresh(socket) do
    project = socket.assigns.sidebar_project

    socket =
      if project && project.path do
        expanded = socket.assigns.flyout_file_expanded

        # Re-fetch children for every currently expanded path.
        # Prune any that fail (dir deleted or unreadable since last expand).
        refreshed_children =
          expanded
          |> Enum.reduce(%{}, fn path, acc ->
            case FileTree.children(project.path, path) do
              {:ok, nodes} -> Map.put(acc, path, nodes)
              {:error, _} -> acc
            end
          end)

        # Prune expanded set to only paths that successfully re-fetched.
        valid_expanded =
          expanded
          |> Enum.filter(&Map.has_key?(refreshed_children, &1))
          |> MapSet.new()

        case FileTree.root(project.path) do
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
      else
        socket
      end

    {:noreply, socket}
  end
end
