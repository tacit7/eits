defmodule EyeInTheSky.ProjectFiles do
  @moduledoc """
  Filesystem helpers for reading and scanning project directories.
  """

  @max_tree_depth 2

  @doc """
  Recursively scans `current_dir` relative to `base_dir`, up to `@max_tree_depth` levels.
  Hidden entries (dot-prefixed names) are excluded.
  Returns a sorted list of entry maps with keys `:name`, `:path`, `:relative`, `:is_dir`,
  and either `:children` (directories) or `:size` (files).
  """
  @spec scan_directory(String.t(), String.t(), non_neg_integer()) :: [map()]
  def scan_directory(base_dir, current_dir, depth) do
    case File.ls(current_dir) do
      {:ok, items} ->
        items
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.sort()
        |> Enum.map(&build_scan_entry(base_dir, current_dir, depth, &1))
        |> Enum.sort_by(&{!&1.is_dir, &1.name})

      _ ->
        []
    end
  end

  defp build_scan_entry(base_dir, current_dir, depth, item) do
    full = Path.join(current_dir, item)
    relative = Path.relative_to(full, base_dir)

    if File.dir?(full) do
      children = if depth < @max_tree_depth, do: scan_directory(base_dir, full, depth + 1), else: []
      %{name: item, path: full, relative: relative, is_dir: true, children: children}
    else
      size = case File.stat(full) do
        {:ok, %{size: s}} -> s
        _ -> 0
      end
      %{name: item, path: full, relative: relative, is_dir: false, size: size}
    end
  end

  @doc """
  Lists the direct children of `full_path`, sorted directories-first.
  `rel_path` is prepended to each entry's `:path` key; pass `nil` for root.
  Returns `{:ok, entries}` or `{:error, reason}`.
  Each entry is `%{name, path, is_dir, size}`.
  """
  @spec list_directory_entries(String.t(), String.t() | nil) ::
          {:ok, [map()]} | {:error, term()}
  def list_directory_entries(full_path, rel_path \\ nil) do
    case File.ls(full_path) do
      {:ok, items} ->
        entries =
          items
          |> Enum.sort()
          |> Enum.map(&build_dir_entry(full_path, rel_path, &1))
          |> Enum.sort_by(&{!&1.is_dir, &1.name})

        {:ok, entries}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_dir_entry(full_path, rel_path, item) do
    item_path = Path.join(full_path, item)
    rel = if rel_path, do: Path.join(rel_path, item), else: item
    size = case File.stat(item_path) do
      {:ok, %{size: s}} -> s
      _ -> 0
    end
    %{name: item, path: rel, is_dir: File.dir?(item_path), size: size}
  end

  @doc """
  Reads a file at `full_path` if it is 1 MB or smaller.
  Returns `{:ok, content}`, `{:too_large, size}`, or `{:error, reason}`.
  """
  @spec read_file(String.t()) ::
          {:ok, String.t()} | {:too_large, non_neg_integer()} | {:error, term()}
  def read_file(full_path) do
    case File.stat(full_path) do
      {:ok, %{size: size}} when size > 1_048_576 ->
        {:too_large, size}

      {:ok, _} ->
        File.read(full_path)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
