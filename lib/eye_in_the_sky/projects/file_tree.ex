defmodule EyeInTheSky.Projects.FileTree do
  @moduledoc """
  Safe filesystem service for project file browsing and editing.

  All functions take a root_path string, not a Project struct.
  Callers decide the root: project.path, session.worktree_path, etc.
  """

  @max_file_size 1_000_000
  @max_entries_per_directory 500

  @ignored_directories ~w(.git node_modules _build deps .elixir_ls coverage tmp)
  @ignored_temp_regex ~r/^\..*\.tmp-[A-Za-z0-9_-]+$/

  # --- Public API ---

  @doc """
  List root directory entries.
  """
  def root(root_path, opts \\ []) do
    children(root_path, "", opts)
  end

  @doc """
  List children of a directory.
  """
  def children(root_path, rel_path, opts \\ []) do
    with :ok <- validate_root_path(root_path),
         {:ok, abs_path} <- safe_path(root_path, rel_path),
         {:ok, _real_path} <- validate_real_path_inside_root(abs_path, root_path) do
      list_directory(abs_path, root_path, opts)
    end
  end

  @doc """
  Read a file's content.
  """
  def read_file(root_path, rel_path, _opts \\ []) do
    with :ok <- validate_root_path(root_path),
         :ok <- validate_file_path(rel_path),
         {:ok, abs_path} <- safe_path(root_path, rel_path),
         {:ok, _real_path} <- validate_real_path_inside_root(abs_path, root_path),
         {:ok, symlink?} <- check_if_symlink(abs_path),
         {:ok, abs_path} <- check_symlink_safety(abs_path, root_path),
         {:ok, stat} <- stat_file(abs_path),
         :ok <- validate_file_type(stat),
         :ok <- validate_file_size(stat),
         {:ok, content} <- File.read(abs_path),
         :ok <- validate_not_binary(content),
         :ok <- validate_utf8(content) do
      hash = hash_content(content)
      language = detect_language(rel_path)

      {:ok,
       %{
         content: content,
         hash: hash,
         size: stat.size,
         language: language,
         symlink?: symlink?,
         editable?: not symlink?,
         sensitive?: sensitive?(rel_path)
       }}
    end
  end

  @doc """
  Write content to a file with conflict detection.

  Options:
  - `original_hash:` - required unless force? is true
  - `force?:` - skip conflict check (default false)
  """
  def write_file(root_path, rel_path, content, opts \\ []) do
    force? = Keyword.get(opts, :force?, false)
    original_hash = Keyword.get(opts, :original_hash)

    with :ok <- validate_root_path(root_path),
         :ok <- validate_file_path(rel_path),
         {:ok, abs_path} <- safe_path(root_path, rel_path),
         {:ok, _real_path} <- validate_real_path_inside_root(abs_path, root_path),
         :ok <- validate_utf8(content),
         {:ok, stat} <- stat_for_write(abs_path),
         :ok <- validate_write_target(stat),
         :ok <- check_conflict(abs_path, original_hash, force?) do
      atomic_write(abs_path, content)
    end
  end

  @doc """
  Resolve a safe lexical path. Prevents path traversal.
  """
  def safe_path(root_path, rel_path) do
    root = Path.expand(root_path)
    rel_path = to_string(rel_path)

    if Path.type(rel_path) == :absolute do
      {:error, :absolute_path_not_allowed}
    else
      target = Path.expand(Path.join(root, rel_path))

      if target == root or String.starts_with?(target, root <> "/") do
        {:ok, target}
      else
        {:error, :outside_project}
      end
    end
  end

  # --- Path Validation ---

  defp validate_root_path(nil), do: {:error, :missing_root_path}
  defp validate_root_path(""), do: {:error, :missing_root_path}

  defp validate_root_path(root_path) do
    case File.stat(root_path) do
      {:ok, %{type: :directory}} -> :ok
      {:ok, _} -> {:error, :root_path_not_directory}
      {:error, :enoent} -> {:error, :root_path_not_found}
      {:error, :eacces} -> {:error, :permission_denied}
      {:error, _} -> {:error, :root_path_not_found}
    end
  end

  defp validate_file_path(""), do: {:error, :missing_file_path}
  defp validate_file_path(nil), do: {:error, :missing_file_path}
  defp validate_file_path(_), do: :ok

  # --- Symlink Safety ---

  # Resolves the full real path (following all symlinks in the path chain)
  # and validates it stays inside the project root.
  # This catches symlinked ancestor directories that escape the project.
  defp validate_real_path_inside_root(abs_path, root_path) do
    # Resolve the real root path (in case root itself contains symlinks like /var -> /private/var)
    {:ok, real_root} = resolve_path_via_parent(Path.expand(root_path))

    # For existing paths, resolve the real path
    # For non-existing paths (new files), resolve parent directory
    real_path =
      case File.exists?(abs_path) do
        true ->
          resolve_path_via_parent(abs_path)

        false ->
          # Path doesn't exist - resolve parent and append basename
          parent = Path.dirname(abs_path)
          basename = Path.basename(abs_path)

          case File.exists?(parent) do
            true ->
              case resolve_path_via_parent(parent) do
                {:ok, real_parent} -> {:ok, Path.join(real_parent, basename)}
                error -> error
              end

            false ->
              # Parent doesn't exist either - use lexical path
              {:ok, abs_path}
          end
      end

    case real_path do
      {:ok, resolved} ->
        if resolved == real_root or String.starts_with?(resolved, real_root <> "/") do
          {:ok, resolved}
        else
          {:error, :symlink_escapes_project}
        end

      {:error, _} = error ->
        error
    end
  end

  # Resolve path by resolving each component, following symlinks at each level
  defp resolve_path_via_parent(path) do
    parent = Path.dirname(path)
    basename = Path.basename(path)

    if parent == path do
      # Root directory
      {:ok, path}
    else
      case resolve_path_via_parent(parent) do
        {:ok, real_parent} ->
          full_path = Path.join(real_parent, basename)

          # Check if this component is a symlink
          case File.read_link(full_path) do
            {:ok, target} ->
              resolved =
                if Path.type(target) == :absolute do
                  target
                else
                  Path.expand(target, real_parent)
                end

              # Recursively resolve the target
              resolve_path_via_parent(resolved)

            {:error, :einval} ->
              # Not a symlink
              {:ok, full_path}

            {:error, :enoent} ->
              # Doesn't exist - return the path anyway
              {:ok, full_path}

            {:error, _} ->
              {:ok, full_path}
          end

        error ->
          error
      end
    end
  end

  defp check_if_symlink(abs_path) do
    case File.lstat(abs_path) do
      {:ok, %{type: :symlink}} -> {:ok, true}
      {:ok, _} -> {:ok, false}
      {:error, :enoent} -> {:error, :file_not_found}
      {:error, :eacces} -> {:error, :permission_denied}
      {:error, _} -> {:error, :file_not_found}
    end
  end

  defp check_symlink_safety(abs_path, root_path) do
    case File.lstat(abs_path) do
      {:ok, %{type: :symlink}} ->
        resolve_symlink(abs_path, root_path)

      {:ok, _} ->
        {:ok, abs_path}

      {:error, :enoent} ->
        {:error, :file_not_found}

      {:error, :eacces} ->
        {:error, :permission_denied}

      {:error, _} ->
        {:error, :file_not_found}
    end
  end

  defp resolve_symlink(abs_path, root_path) do
    case resolve_symlink_chain(abs_path, MapSet.new()) do
      {:ok, resolved} ->
        root = Path.expand(root_path)

        if String.starts_with?(resolved, root <> "/") do
          {:ok, resolved}
        else
          {:error, :symlink_escapes_project}
        end

      {:error, _} = error ->
        error
    end
  end

  defp resolve_symlink_chain(path, seen) do
    if MapSet.member?(seen, path) do
      {:error, :symlink_loop}
    else
      case File.read_link(path) do
        {:ok, target} ->
          resolved =
            if Path.type(target) == :absolute do
              target
            else
              Path.expand(target, Path.dirname(path))
            end

          case File.lstat(resolved) do
            {:ok, %{type: :symlink}} ->
              resolve_symlink_chain(resolved, MapSet.put(seen, path))

            {:ok, _} ->
              {:ok, resolved}

            {:error, :enoent} ->
              {:error, :broken_symlink}

            {:error, _} ->
              {:error, :broken_symlink}
          end

        {:error, :einval} ->
          {:ok, path}

        {:error, :enoent} ->
          {:error, :broken_symlink}

        {:error, _} ->
          {:error, :broken_symlink}
      end
    end
  end

  # --- Directory Listing ---

  defp list_directory(abs_path, root_path, _opts) do
    case File.ls(abs_path) do
      {:ok, entries} ->
        root = Path.expand(root_path)

        nodes =
          entries
          |> Enum.reject(&ignored?/1)
          |> Enum.map(fn name ->
            entry_path = Path.join(abs_path, name)
            rel_path = Path.relative_to(entry_path, root)
            build_node(name, entry_path, rel_path)
          end)
          |> Enum.sort_by(fn node ->
            {if(node.type == :directory, do: 0, else: 1), String.downcase(node.name)}
          end)

        {nodes, truncated?} =
          if length(nodes) > @max_entries_per_directory do
            {Enum.take(nodes, @max_entries_per_directory), true}
          else
            {nodes, false}
          end

        nodes =
          if truncated? do
            nodes ++
              [
                %{
                  name:
                    "This directory has more than #{@max_entries_per_directory} entries. Some entries are hidden.",
                  path: nil,
                  type: :warning,
                  symlink?: false,
                  expandable?: false,
                  editable?: false,
                  sensitive?: false
                }
              ]
          else
            nodes
          end

        {:ok, nodes}

      {:error, :enoent} ->
        {:error, :path_not_found}

      {:error, :eacces} ->
        {:error, :permission_denied}

      {:error, :enotdir} ->
        {:error, :path_is_directory}

      {:error, _} ->
        {:error, :permission_denied}
    end
  end

  defp build_node(name, entry_path, rel_path) do
    case File.lstat(entry_path) do
      {:ok, %{type: :symlink} = _stat} ->
        case File.stat(entry_path) do
          {:ok, %{type: :directory}} ->
            %{
              name: name,
              path: rel_path,
              type: :directory,
              symlink?: true,
              expandable?: false,
              editable?: false,
              sensitive?: false
            }

          {:ok, %{type: :regular}} ->
            %{
              name: name,
              path: rel_path,
              type: :file,
              symlink?: true,
              expandable?: false,
              editable?: false,
              sensitive?: sensitive?(rel_path)
            }

          _ ->
            %{
              name: name,
              path: rel_path,
              type: :file,
              symlink?: true,
              expandable?: false,
              editable?: false,
              sensitive?: false
            }
        end

      {:ok, %{type: :directory}} ->
        %{
          name: name,
          path: rel_path,
          type: :directory,
          symlink?: false,
          expandable?: true,
          editable?: false,
          sensitive?: false
        }

      {:ok, %{type: :regular}} ->
        %{
          name: name,
          path: rel_path,
          type: :file,
          symlink?: false,
          expandable?: false,
          editable?: true,
          sensitive?: sensitive?(rel_path)
        }

      _ ->
        %{
          name: name,
          path: rel_path,
          type: :file,
          symlink?: false,
          expandable?: false,
          editable?: false,
          sensitive?: false
        }
    end
  end

  defp ignored?(name) do
    name in @ignored_directories or Regex.match?(@ignored_temp_regex, name)
  end

  # --- File Validation ---

  defp stat_file(abs_path) do
    case File.stat(abs_path) do
      {:ok, stat} -> {:ok, stat}
      {:error, :enoent} -> {:error, :file_not_found}
      {:error, :eacces} -> {:error, :permission_denied}
      {:error, _} -> {:error, :file_not_found}
    end
  end

  defp stat_for_write(abs_path) do
    case File.lstat(abs_path) do
      {:ok, stat} -> {:ok, stat}
      {:error, :enoent} -> {:error, :file_deleted}
      {:error, :eacces} -> {:error, :permission_denied}
      {:error, _} -> {:error, :file_deleted}
    end
  end

  defp validate_file_type(%{type: :directory}), do: {:error, :path_is_directory}
  defp validate_file_type(%{type: :regular}), do: :ok
  defp validate_file_type(%{type: :symlink}), do: :ok
  defp validate_file_type(_), do: {:error, :unsupported_file_type}

  defp validate_write_target(%{type: :directory}), do: {:error, :path_is_directory}
  defp validate_write_target(%{type: :symlink}), do: {:error, :symlink_not_saveable}
  defp validate_write_target(%{type: :regular}), do: :ok
  defp validate_write_target(_), do: {:error, :unsupported_file_type}

  defp validate_file_size(%{size: size}) when size > @max_file_size do
    {:error, :file_too_large}
  end

  defp validate_file_size(_), do: :ok

  defp validate_not_binary(content) do
    if binary_file?(content) do
      {:error, :binary_file}
    else
      :ok
    end
  end

  defp validate_utf8(content) do
    if String.valid?(content) do
      :ok
    else
      {:error, :invalid_utf8}
    end
  end

  defp binary_file?(content) do
    :binary.match(content, <<0>>) != :nomatch
  end

  # --- Conflict Detection ---

  defp check_conflict(_abs_path, _original_hash, true = _force?), do: :ok

  defp check_conflict(_abs_path, nil, false) do
    {:error, :missing_original_hash}
  end

  defp check_conflict(abs_path, original_hash, false) do
    case File.read(abs_path) do
      {:ok, current_content} ->
        current_hash = hash_content(current_content)

        if current_hash == original_hash do
          :ok
        else
          {:error, :conflict}
        end

      {:error, _} ->
        {:error, :file_deleted}
    end
  end

  defp hash_content(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  # --- Atomic Write ---

  defp atomic_write(path, content) do
    dir = Path.dirname(path)
    base = Path.basename(path)
    random = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    tmp_path = Path.join(dir, ".#{base}.tmp-#{random}")

    original_mode =
      case File.stat(path) do
        {:ok, %{mode: mode}} -> mode
        _ -> nil
      end

    with :ok <- File.write(tmp_path, content),
         :ok <- maybe_chmod(tmp_path, original_mode),
         :ok <- File.rename(tmp_path, path) do
      new_hash = hash_content(content)
      {:ok, %{hash: new_hash}}
    else
      {:error, _reason} = error ->
        File.rm(tmp_path)
        error

      error ->
        File.rm(tmp_path)
        {:error, error}
    end
  end

  defp maybe_chmod(_path, nil), do: :ok
  defp maybe_chmod(path, mode), do: File.chmod(path, mode)

  # --- Language Detection ---

  @language_map %{
    ".ex" => :elixir,
    ".exs" => :elixir,
    ".heex" => :html,
    ".js" => :javascript,
    ".ts" => :typescript,
    ".svelte" => :svelte,
    ".md" => :markdown,
    ".json" => :json,
    ".html" => :html,
    ".css" => :css,
    ".yml" => :yaml,
    ".yaml" => :yaml
  }

  defp detect_language(rel_path) do
    ext = Path.extname(rel_path)
    Map.get(@language_map, ext, :plaintext)
  end

  # --- Sensitive Files ---

  @doc """
  Check if a file is sensitive (e.g., .env, credentials).
  """
  def sensitive?(rel_path) do
    basename = Path.basename(rel_path)

    String.match?(basename, ~r/^\.env(\..*)?$/) or
      String.ends_with?(basename, ".pem") or
      String.ends_with?(basename, ".key") or
      basename == "credentials.json" or
      rel_path == "config/prod.secret.exs"
  end
end
