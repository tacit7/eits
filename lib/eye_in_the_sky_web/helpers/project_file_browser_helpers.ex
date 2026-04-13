defmodule EyeInTheSkyWeb.Helpers.ProjectFileBrowserHelpers do
  @moduledoc """
  Shared helpers for LiveViews that browse and display project files.
  Handles path security checks and file-read result assignment.
  """

  import Phoenix.Component, only: [assign: 3]
  import EyeInTheSkyWeb.Helpers.FileHelpers, only: [detect_file_type: 1]

  @max_file_size 1_048_576

  @doc """
  Returns true when `path` is within `base_dir` (after path expansion).
  Prevents directory traversal attacks.
  """
  def path_within?(path, base_dir) do
    expanded_path = Path.expand(path)
    expanded_base = Path.expand(base_dir)
    expanded_path == expanded_base or String.starts_with?(expanded_path, expanded_base <> "/")
  end

  @doc """
  Reads a file with a size guard.
  Returns {:ok, content} | {:too_large} | {:error, reason}.

  Both stat failures and read failures return {:error, reason}. Callers that need
  to distinguish stat errors from read errors should use read_file_safe_detailed/1.
  """
  def read_file_safe(full_path) do
    case File.stat(full_path) do
      {:ok, %{size: size}} when size > @max_file_size ->
        {:too_large}

      {:ok, _stat} ->
        case File.read(full_path) do
          {:ok, content} -> {:ok, content}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reads a file with a size guard, preserving error source distinction.
  Returns {:ok, content} | {:too_large} | {:read_error, reason} | {:stat_error, reason}.

  Callers that need "Failed to stat file" vs "Failed to read file" error message
  parity should use this variant instead of read_file_safe/1.
  """
  def read_file_safe_detailed(full_path) do
    case File.stat(full_path) do
      {:ok, %{size: size}} when size > @max_file_size ->
        {:too_large}

      {:ok, _stat} ->
        case File.read(full_path) do
          {:ok, content} -> {:ok, content}
          {:error, reason} -> {:read_error, reason}
        end

      {:error, reason} ->
        {:stat_error, reason}
    end
  end

  @doc """
  Assigns file content to socket after a security-checked read.
  Sets :file_content, :file_type, :selected_file, :selected_file_path, :error.
  Returns {:ok, socket} | {:error, socket} (with :error assigned).

  Error messages match the originals from ProjectLive.Config and ProjectLive.Files:
  - too large     -> "File too large to display (over 1 MB)"
  - read failure  -> "Failed to read file: <reason>"
  - stat failure  -> "Failed to stat file: <reason>"
  - access denied -> "Access denied"

  Use for LiveViews that track the open file via :selected_file/:selected_file_path
  (e.g. ProjectLive.Config).
  """
  def assign_file_read(socket, full_path, rel_path, base_dir) do
    if path_within?(full_path, base_dir) do
      case read_file_safe_detailed(full_path) do
        {:ok, content} ->
          socket =
            socket
            |> assign(:file_content, content)
            |> assign(:file_type, detect_file_type(full_path))
            |> assign(:selected_file, rel_path)
            |> assign(:selected_file_path, full_path)
            |> assign(:error, nil)

          {:ok, socket}

        {:too_large} ->
          {:error, assign(socket, :error, "File too large to display (over 1 MB)")}

        {:read_error, reason} ->
          {:error, assign(socket, :error, "Failed to read file: #{reason}")}

        {:stat_error, reason} ->
          {:error, assign(socket, :error, "Failed to stat file: #{reason}")}
      end
    else
      {:error, assign(socket, :error, "Access denied")}
    end
  end

  @doc """
  Clears file viewer assigns. Call from close_viewer event handler.
  """
  def clear_file_assigns(socket) do
    socket
    |> assign(:selected_file, nil)
    |> assign(:selected_file_path, nil)
    |> assign(:file_content, nil)
    |> assign(:file_type, nil)
  end

  # ── Pure file-browser I/O helpers ────────────────────────────────────────────
  # These take and return plain values — no socket manipulation.

  @max_tree_depth 2

  @doc """
  Recursively scans a directory up to @max_tree_depth levels deep.
  Returns a sorted list of entry maps with :name, :path, :relative, :is_dir,
  :children (for dirs), and :size (for files).
  Hidden entries (names starting with ".") are skipped.
  """
  def scan_directory(base_dir, current_dir, depth) do
    case File.ls(current_dir) do
      {:ok, items} ->
        items
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.sort()
        |> Enum.map(fn item ->
          full = Path.join(current_dir, item)
          relative = Path.relative_to(full, base_dir)
          is_dir = File.dir?(full)

          if is_dir do
            children =
              if depth < @max_tree_depth,
                do: scan_directory(base_dir, full, depth + 1),
                else: []

            %{name: item, path: full, relative: relative, is_dir: true, children: children}
          else
            size =
              case File.stat(full) do
                {:ok, %{size: s}} -> s
                _ -> 0
              end

            %{name: item, path: full, relative: relative, is_dir: false, size: size}
          end
        end)
        |> Enum.sort_by(&{!&1.is_dir, &1.name})

      _ ->
        []
    end
  end

  @doc """
  Resolves the target path for list-mode navigation.
  Returns {:ok, full_path, rel_path} | {:error, message}.
  """
  def resolve_list_target(path, base_dir) do
    if path && path != "" do
      full = Path.join(base_dir, path)
      if path_within?(full, base_dir), do: {:ok, full, path}, else: {:error, "Access denied"}
    else
      {:ok, base_dir, nil}
    end
  end

  @doc """
  Builds a file-entry map for a single item within a directory listing.
  """
  def build_file_entry(item, dir_path, rel_path) do
    item_path = Path.join(dir_path, item)
    rel = if rel_path, do: Path.join(rel_path, item), else: item

    size =
      case File.stat(item_path) do
        {:ok, %{size: s}} -> s
        _ -> 0
      end

    %{name: item, path: rel, is_dir: File.dir?(item_path), size: size}
  end

  @doc """
  Lists a directory and returns a sorted list of entry maps.
  Returns {:ok, entries} | {:error, message}.
  """
  def list_directory(full_path, rel_path) do
    case File.ls(full_path) do
      {:ok, items} ->
        file_list =
          items
          |> Enum.sort()
          |> Enum.map(&build_file_entry(&1, full_path, rel_path))
          |> Enum.sort_by(&{!&1.is_dir, &1.name})

        {:ok, file_list}

      {:error, reason} ->
        {:error, "Failed to read directory: #{reason}"}
    end
  end

  @doc """
  Dispatches a resolved path to the appropriate result type.
  Returns {:dir, files, rel_path} | {:file, full_path, rel_path} | {:error, message}.
  """
  def dispatch_path(full_path, rel_path, raw_path, _base_dir) do
    cond do
      File.dir?(full_path) ->
        case list_directory(full_path, rel_path) do
          {:ok, files} -> {:dir, files, rel_path}
          {:error, msg} -> {:error, msg}
        end

      File.regular?(full_path) ->
        {:file, full_path, rel_path}

      true ->
        {:error, "Path not found: #{raw_path}"}
    end
  end
end
