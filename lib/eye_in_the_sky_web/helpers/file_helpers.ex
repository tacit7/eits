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
    path |> Path.extname() |> String.downcase() |> file_type_info() |> Map.get(:atom)
  end

  @language_classes %{
    markdown: "markdown",
    elixir: "elixir",
    javascript: "javascript",
    typescript: "typescript",
    json: "json",
    yaml: "yaml",
    html: "html",
    css: "css",
    python: "python",
    ruby: "ruby",
    go: "go",
    rust: "rust",
    java: "java",
    c: "c",
    cpp: "cpp",
    bash: "bash",
    sql: "sql",
    xml: "xml",
    toml: "toml"
  }

  @spec language_class(atom) :: String.t()
  def language_class(file_type), do: Map.get(@language_classes, file_type, "plaintext")

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

  @spec cm_language(String.t()) :: String.t()
  def cm_language(path) when is_binary(path) do
    path |> Path.extname() |> String.downcase() |> file_type_info() |> Map.get(:cm)
  end

  def cm_language(_), do: "text"

  @file_types %{
    ".md" => %{atom: :markdown, class: "markdown", cm: "markdown"},
    ".markdown" => %{atom: :markdown, class: "markdown", cm: "markdown"},
    ".ex" => %{atom: :elixir, class: "elixir", cm: "elixir"},
    ".exs" => %{atom: :elixir, class: "elixir", cm: "elixir"},
    ".js" => %{atom: :javascript, class: "javascript", cm: "javascript"},
    ".jsx" => %{atom: :javascript, class: "javascript", cm: "javascript"},
    ".ts" => %{atom: :typescript, class: "typescript", cm: "javascript"},
    ".tsx" => %{atom: :typescript, class: "typescript", cm: "javascript"},
    ".json" => %{atom: :json, class: "json", cm: "json"},
    ".yml" => %{atom: :yaml, class: "yaml", cm: "yaml"},
    ".yaml" => %{atom: :yaml, class: "yaml", cm: "yaml"},
    ".html" => %{atom: :html, class: "html", cm: "html"},
    ".heex" => %{atom: :html, class: "html", cm: "html"},
    ".css" => %{atom: :css, class: "css", cm: "css"},
    ".py" => %{atom: :python, class: "python", cm: "text"},
    ".rb" => %{atom: :ruby, class: "ruby", cm: "text"},
    ".go" => %{atom: :go, class: "go", cm: "text"},
    ".rs" => %{atom: :rust, class: "rust", cm: "text"},
    ".java" => %{atom: :java, class: "java", cm: "text"},
    ".c" => %{atom: :c, class: "c", cm: "text"},
    ".cpp" => %{atom: :cpp, class: "cpp", cm: "text"},
    ".sh" => %{atom: :bash, class: "bash", cm: "shell"},
    ".bash" => %{atom: :bash, class: "bash", cm: "shell"},
    ".sql" => %{atom: :sql, class: "sql", cm: "text"},
    ".xml" => %{atom: :xml, class: "xml", cm: "text"},
    ".toml" => %{atom: :toml, class: "toml", cm: "text"}
  }

  defp file_type_info(ext), do: Map.get(@file_types, ext, %{atom: :text, class: "plaintext", cm: "text"})

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
        entries =
          for file <- files,
              full_path = Path.join(current_path, file),
              (!String.starts_with?(file, ".") or file in [".claude", ".git"]) and
                file not in ignored_dirs and
                (File.dir?(full_path) or !binary_file?(full_path)),
              do: build_tree_entry(base_path, current_path, file, max_depth, current_depth)

        Enum.sort_by(entries, &{&1.type != :directory, &1.name})

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

  @base_icon_path "/images/file-icons"

  @file_icon_map %{
    # Elixir
    ".ex" => "file_type_elixir",
    ".exs" => "file_type_elixir",
    # JavaScript
    ".js" => "file_type_js",
    ".jsx" => "file_type_js",
    ".mjs" => "file_type_js",
    # TypeScript
    ".ts" => "file_type_typescript",
    ".tsx" => "file_type_typescript",
    # Svelte
    ".svelte" => "file_type_svelte",
    # Python
    ".py" => "file_type_python",
    # Ruby
    ".rb" => "file_type_ruby",
    # Go
    ".go" => "file_type_go",
    # Rust
    ".rs" => "file_type_rust",
    # Java
    ".java" => "file_type_java",
    # C/C++
    ".c" => "file_type_c",
    ".h" => "file_type_c",
    ".cpp" => "file_type_cpp",
    ".cc" => "file_type_cpp",
    ".cxx" => "file_type_cpp",
    ".hpp" => "file_type_cpp",
    # Shell
    ".sh" => "file_type_shell",
    ".bash" => "file_type_shell",
    ".zsh" => "file_type_shell",
    # SQL
    ".sql" => "file_type_sql",
    # CSS
    ".css" => "file_type_css",
    ".scss" => "file_type_css",
    ".sass" => "file_type_css",
    # HTML
    ".html" => "file_type_html",
    ".heex" => "file_type_html",
    ".htm" => "file_type_html",
    # Markdown
    ".md" => "file_type_markdown",
    ".markdown" => "file_type_markdown",
    # JSON
    ".json" => "file_type_json",
    # YAML
    ".yml" => "file_type_yaml",
    ".yaml" => "file_type_yaml",
    # XML
    ".xml" => "file_type_xml",
    # TOML
    ".toml" => "file_type_toml",
    # Config / lock
    ".lock" => "file_type_config",
    ".conf" => "file_type_config"
  }

  @filename_icon_map %{
    ".gitignore" => "file_type_git",
    ".gitattributes" => "file_type_git",
    ".gitmodules" => "file_type_git",
    ".env" => "file_type_dotenv",
    ".env.example" => "file_type_dotenv",
    ".env.local" => "file_type_dotenv",
    ".env.test" => "file_type_dotenv",
    ".env.prod" => "file_type_dotenv",
    "Dockerfile" => "file_type_docker",
    "docker-compose.yml" => "file_type_yaml",
    "docker-compose.yaml" => "file_type_yaml",
    "mix.exs" => "file_type_elixir",
    "mix.lock" => "file_type_config"
  }

  @folder_icon_map %{
    "lib" => "folder_type_library",
    "test" => "folder_type_test",
    "tests" => "folder_type_test",
    "spec" => "folder_type_test",
    "config" => "folder_type_config",
    ".git" => "folder_type_git",
    "node_modules" => "folder_type_node",
    "assets" => "folder_type_public",
    "priv" => "folder_type_private",
    "src" => "folder_type_src",
    "deps" => "folder_type_library",
    "_build" => "folder_type_library",
    "docker" => "folder_type_docker"
  }

  @doc """
  Returns the `/images/file-icons/` URL for a file path, based on filename then extension.
  Falls back to the default file icon.
  """
  @spec file_icon_src(String.t()) :: String.t()
  def file_icon_src(path) when is_binary(path) do
    basename = Path.basename(path)
    ext = path |> Path.extname() |> String.downcase()

    icon =
      Map.get(@filename_icon_map, basename) ||
        Map.get(@file_icon_map, ext) ||
        "default_file"

    "#{@base_icon_path}/#{icon}.svg"
  end

  def file_icon_src(_), do: "#{@base_icon_path}/default_file.svg"

  @doc """
  Returns the `/images/file-icons/` URL for a directory, based on its name.
  Pass `expanded: true` for the open-folder variant.
  Falls back to the default folder icon.
  """
  @spec folder_icon_src(String.t(), keyword()) :: String.t()
  def folder_icon_src(path, opts \\ [])

  def folder_icon_src(path, opts) when is_binary(path) do
    expanded = Keyword.get(opts, :expanded, false)
    name = Path.basename(path)
    base = Map.get(@folder_icon_map, name, "default_folder")
    suffix = if expanded, do: "_opened", else: ""
    "#{@base_icon_path}/#{base}#{suffix}.svg"
  end

  def folder_icon_src(_, _), do: "#{@base_icon_path}/default_folder.svg"

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
