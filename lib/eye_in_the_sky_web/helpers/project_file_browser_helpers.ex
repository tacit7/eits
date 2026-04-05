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
    String.starts_with?(Path.expand(path), Path.expand(base_dir))
  end

  @doc """
  Reads a file with a size guard.
  Returns {:ok, content} | {:too_large} | {:error, reason}.
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
  Assigns file content to socket after a security-checked read.
  Sets :file_content, :file_type, :selected_file, :selected_file_path, :error.
  Returns {:ok, socket} | {:error, socket} (with :error assigned).

  Use for LiveViews that track the open file via :selected_file/:selected_file_path
  (e.g. ProjectLive.Config).
  """
  def assign_file_read(socket, full_path, rel_path, base_dir) do
    if path_within?(full_path, base_dir) do
      case read_file_safe(full_path) do
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

        {:error, reason} ->
          {:error, assign(socket, :error, "Failed to read file: #{reason}")}
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
end
