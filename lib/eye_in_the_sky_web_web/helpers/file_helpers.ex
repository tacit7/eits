defmodule EyeInTheSkyWebWeb.Helpers.FileHelpers do
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

  @spec format_size(integer) :: String.t()
  def format_size(size) when is_integer(size) and size < 1024, do: "#{size} B"

  def format_size(size) when is_integer(size) and size < 1024 * 1024,
    do: "#{Float.round(size / 1024, 1)} KB"

  def format_size(size) when is_integer(size),
    do: "#{Float.round(size / (1024 * 1024), 1)} MB"

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
      _ -> "plaintext"
    end
  end

  @doc """
  Recursively builds a file tree up to `max_depth`.
  Returns a list of %{name, path, type, children?/size} maps.
  """
  @spec build_file_tree(String.t(), String.t(), non_neg_integer, non_neg_integer) :: list(map())
  def build_file_tree(base_path, current_path, max_depth \\ 5, current_depth \\ 0) do
    if current_depth >= max_depth do
      []
    else
      case File.ls(current_path) do
        {:ok, files} ->
          files
          |> Enum.filter(fn file ->
            not String.starts_with?(file, ".") or file in [".claude", ".git"]
          end)
          |> Enum.map(fn file ->
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
          end)
          |> Enum.sort_by(&{&1.type != :directory, &1.name})

        {:error, _reason} ->
          []
      end
    end
  end
end
