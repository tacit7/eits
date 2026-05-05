defmodule EyeInTheSkyWeb.DmLive.FileAutocomplete do
  @moduledoc """
  Server-side file listing for the DM composer @ autocomplete trigger.

  `list_entries/3` resolves the root, guards against path traversal, lists
  matching directory entries, and returns insertion-safe `insert_text` values
  the client pastes directly into the textarea.
  """

  @root_excluded_dirs ~w(.git node_modules deps _build .elixir_ls .tmp)
  @max_entries 50

  @doc """
  Lists filesystem entries for the given partial path and root type.

  Returns `%{entries: [...], truncated: boolean}`. Returns empty on any error.

  Each entry: `%{name: String.t(), path: String.t(), insert_text: String.t(), is_dir: boolean()}`.
  - `path` — root-relative path; pass back as `partial` for follow-up fetches
  - `insert_text` — exact string to insert into the textarea (includes `@` prefix)
  """
  @spec list_entries(String.t(), String.t(), map()) :: %{entries: list(), truncated: boolean()}
  def list_entries(partial, root_type, session) do
    case resolve_base(root_type, session) do
      {:ok, base_dir} ->
        {dir_part, file_prefix} = split_partial(partial)
        target = Path.expand(Path.join(base_dir, dir_part))

        if under_root?(target, base_dir) do
          case File.ls(target) do
            {:ok, names} -> build_result(names, target, dir_part, file_prefix, root_type)
            _ -> empty()
          end
        else
          empty()
        end

      _ ->
        empty()
    end
  end

  @doc """
  Returns true when `path` is equal to `root` or a direct descendant.
  Handles filesystem root `/` without producing the `//` double-slash bug.
  """
  @spec under_root?(String.t(), String.t()) :: boolean()
  def under_root?(path, root) do
    expanded_path = Path.expand(path)
    expanded_root = Path.expand(root)

    cond do
      expanded_root == "/" ->
        String.starts_with?(expanded_path, "/")

      expanded_path == expanded_root ->
        true

      true ->
        String.starts_with?(expanded_path, expanded_root <> "/")
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp resolve_base("project", session) do
    raw = Map.get(session, :git_worktree_path)

    cond do
      is_binary(raw) and File.dir?(raw) ->
        {:ok, raw}

      true ->
        case File.cwd() do
          {:ok, cwd} -> {:ok, cwd}
          {:error, reason} -> {:error, {:no_cwd, reason}}
        end
    end
  end

  defp resolve_base("home", _session), do: {:ok, Path.expand("~")}
  defp resolve_base("filesystem", _session), do: {:ok, "/"}
  defp resolve_base(_, _), do: {:error, :unknown_root}

  defp split_partial(partial) do
    case String.split(partial, "/") do
      [prefix] ->
        {"", prefix}

      parts ->
        file_prefix = List.last(parts)
        dir_part = parts |> Enum.drop(-1) |> Enum.join("/")
        {dir_part, file_prefix}
    end
  end

  defp build_result(names, target, dir_part, file_prefix, root_type) do
    at_root = dir_part == ""

    filtered =
      names
      |> Enum.reject(fn name -> at_root && name in @root_excluded_dirs end)
      |> Enum.filter(&String.starts_with?(&1, file_prefix))
      |> Enum.take(@max_entries + 1)

    truncated = length(filtered) > @max_entries
    capped = Enum.take(filtered, @max_entries)

    entries =
      capped
      |> Enum.map(fn name ->
        is_dir = File.dir?(Path.join(target, name))
        rel_path = if dir_part == "", do: name, else: "#{dir_part}/#{name}"
        rel_path = if is_dir, do: "#{rel_path}/", else: rel_path
        %{name: name, path: rel_path, insert_text: build_insert_text(rel_path, root_type), is_dir: is_dir}
      end)
      |> Enum.sort_by(&{!&1.is_dir, &1.name})

    %{entries: entries, truncated: truncated}
  end

  defp build_insert_text(rel_path, "home"), do: "@~/#{rel_path}"
  defp build_insert_text(rel_path, "filesystem"), do: "@/#{rel_path}"
  defp build_insert_text(rel_path, _), do: "@#{rel_path}"

  defp empty, do: %{entries: [], truncated: false}
end
