defmodule EyeInTheSkyWeb.Helpers.FileHelpers do
  @moduledoc """
  Helpers for file rendering and metadata (sizes, types, language classes).
  """

  @spec get_file_size(String.t()) :: String.t()
  def get_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> format_size(size)
      _ -> ""
    end
  end

  @spec format_size(integer | any) :: String.t()
  def format_size(size) when is_integer(size) and size < 1024, do: "#{size} B"

  def format_size(size) when is_integer(size) and size < 1024 * 1024,
    do: "#{Float.round(size / 1024, 1)} KB"

  def format_size(size) when is_integer(size),
    do: "#{Float.round(size / (1024 * 1024), 1)} MB"

  def format_size(_), do: ""

  @spec detect_file_type(String.t()) :: atom
  def detect_file_type(path) do
    extension = path |> Path.extname() |> String.downcase()

    case extension do
      ".md" -> :markdown
      ".markdown" -> :markdown
      ".ex" -> :elixir
      ".exs" -> :elixir
      ".js" -> :javascript
      ".ts" -> :typescript
      ".jsx" -> :javascript
      ".tsx" -> :typescript
      ".json" -> :json
      ".yml" -> :yaml
      ".yaml" -> :yaml
      ".html" -> :html
      ".css" -> :css
      ".py" -> :python
      ".rb" -> :ruby
      ".go" -> :go
      ".rs" -> :rust
      ".java" -> :java
      ".c" -> :c
      ".cpp" -> :cpp
      ".sh" -> :bash
      ".sql" -> :sql
      ".xml" -> :xml
      ".toml" -> :toml
      _ -> :text
    end
  end

  @spec language_class(atom) :: String.t()
  def language_class(file_type) do
    case file_type do
      :markdown -> "markdown"
      :elixir -> "elixir"
      :javascript -> "javascript"
      :typescript -> "typescript"
      :json -> "json"
      :yaml -> "yaml"
      :html -> "html"
      :css -> "css"
      :python -> "python"
      :ruby -> "ruby"
      :go -> "go"
      :rust -> "rust"
      :java -> "java"
      :c -> "c"
      :cpp -> "cpp"
      :bash -> "bash"
      :sql -> "sql"
      :xml -> "xml"
      :toml -> "toml"
      _ -> "plaintext"
    end
  end

  @doc """
  Resolves a path to its canonical form, following symlinks.
  Returns `{:ok, realpath}` or `{:error, reason}`.
  """
  @spec safe_realpath(String.t()) :: {:ok, String.t()} | {:error, atom}
  def safe_realpath(path) do
    case System.cmd("realpath", [path], stderr_to_stdout: true) do
      {resolved, 0} -> {:ok, String.trim(resolved)}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Returns true if `child_path` is safely contained within `root_path`,
  resolving symlinks to prevent escape.
  """
  @spec path_within?(String.t(), String.t()) :: boolean
  def path_within?(child_path, root_path) do
    with {:ok, real_root} <- safe_realpath(root_path),
         {:ok, real_child} <- safe_realpath(child_path) do
      String.starts_with?(real_child, real_root <> "/")
    else
      {:error, _} -> false
    end
  end

  @spec cm_language(atom) :: String.t()
  def cm_language(file_type) do
    case file_type do
      :elixir -> "elixir"
      :markdown -> "markdown"
      :javascript -> "javascript"
      :typescript -> "javascript"
      :json -> "json"
      :yaml -> "yaml"
      :html -> "html"
      :css -> "css"
      :bash -> "shell"
      _ -> "text"
    end
  end

  @doc """
  Recursively builds a file tree up to `max_depth`.
  Returns a list of %{name, path, type, children?/size} maps.
  Filters out hidden files (except .claude/.git), common ignored dirs, and binary files.
  """
  @spec build_file_tree(String.t(), String.t(), non_neg_integer, non_neg_integer) :: list(map())
  def build_file_tree(base_path, current_path, max_depth \\ 5, current_depth \\ 0) do
    if current_depth >= max_depth do
      []
    else
      ignored_dirs = ~w(node_modules _build deps dist .elixir_ls __pycache__ target vendor)
      list_tree_files(base_path, current_path, ignored_dirs, max_depth, current_depth)
    end
  end

  defp list_tree_files(base_path, current_path, ignored_dirs, max_depth, current_depth) do
    case File.ls(current_path) do
      {:ok, files} ->
        for file <- files,
            full_path = Path.join(current_path, file),
            (!String.starts_with?(file, ".") or file in [".claude", ".git"]) and
              file not in ignored_dirs and
              (File.dir?(full_path) or !binary_file?(full_path)),
            do: build_tree_entry(base_path, current_path, file, max_depth, current_depth)
        |> Enum.sort_by(&{&1.type != :directory, &1.name})

      {:error, _reason} ->
        []
    end
  end

  defp build_tree_entry(base_path, current_path, file, max_depth, current_depth) do
    full_path = Path.join(current_path, file)
    relative_path = Path.relative_to(full_path, base_path)

    if File.dir?(full_path) do
      children = build_file_tree(base_path, full_path, max_depth, current_depth + 1)

      %{
        name: file,
        path: relative_path,
        type: :directory,
        children: Enum.sort_by(children, &{&1.type != :directory, &1.name})
      }
    else
      %{
        name: file,
        path: relative_path,
        type: :file,
        size: get_file_size(full_path)
      }
    end
  end

  @doc """
  Returns true if the file at `path` is a known binary format based on extension.
  """
  @spec binary_file?(String.t()) :: boolean
  def binary_file?(path) do
    binary_extensions = [
      # Executables and libraries
      ".so",
      ".dll",
      ".dylib",
      ".exe",
      ".bin",
      ".o",
      ".a",
      ".lib",
      # Archives
      ".zip",
      ".tar",
      ".gz",
      ".bz2",
      ".xz",
      ".7z",
      ".rar",
      # Images
      ".jpg",
      ".jpeg",
      ".png",
      ".gif",
      ".bmp",
      ".ico",
      ".svg",
      ".webp",
      # Media
      ".mp3",
      ".mp4",
      ".avi",
      ".mov",
      ".mkv",
      ".wav",
      ".flac",
      # Documents
      ".pdf",
      ".doc",
      ".docx",
      ".xls",
      ".xlsx",
      ".ppt",
      ".pptx",
      # Databases
      ".db",
      ".sqlite",
      ".sqlite3",
      ".db-shm",
      ".db-wal",
      # Others
      ".wasm",
      ".beam",
      ".class",
      ".jar",
      ".war"
    ]

    extension = path |> Path.extname() |> String.downcase()
    Enum.member?(binary_extensions, extension)
  end

  @type file_entry :: %{
          name: String.t(),
          path: String.t(),
          is_dir: boolean(),
          size: non_neg_integer()
        }

  @doc """
  Builds a flat file listing for `dir`, with each entry's `:path` set to
  `Path.join(path_prefix, filename)`. When `path_prefix` is `""` the path
  is just the filename, matching root-level listing behaviour.

  ## Options
    * `:ignore_hidden` - when true, skip dotfiles (except .claude and .git)
    * `:ignored_dirs` - list of directory names to exclude entirely
  """
  @spec build_file_listing(String.t(), String.t(), keyword()) ::
          {:ok, [file_entry()]} | {:error, term()}
  def build_file_listing(dir, path_prefix, opts \\ []) do
    ignore_hidden = Keyword.get(opts, :ignore_hidden, false)
    ignored_dirs = Keyword.get(opts, :ignored_dirs, [])

    case File.ls(dir) do
      {:ok, files} ->
        file_list =
          for file <- files,
              file_path = Path.join(dir, file),
              (!ignore_hidden or !String.starts_with?(file, ".") or file in [".claude", ".git"]) and
                file not in ignored_dirs and
                (File.dir?(file_path) or !binary_file?(file_path)) do
            size =
              case File.stat(file_path) do
                {:ok, %{size: s}} -> s
                _ -> 0
              end

            %{
              name: file,
              path: if(path_prefix == "", do: file, else: Path.join(path_prefix, file)),
              is_dir: File.dir?(file_path),
              size: size
            }
          end
          |> Enum.sort_by(&{!&1.is_dir, &1.name})

        {:ok, file_list}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
