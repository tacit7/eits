defmodule EyeInTheSkyWeb.Live.Shared.DefinitionFileActions do
  @moduledoc """
  Filesystem mutations for agent-definition and skill/command `.md` files.

  Scoped to bare markdown files only — NOT skill directories (a `SKILL.md`
  bundled with sibling reference files under a folder). Duplicating or
  deleting one of those is a materially different, riskier operation (tree
  copy + frontmatter identity rewrite for duplicate; recursive delete for
  removal) that callers should gate out before reaching these functions.
  """

  @doc """
  Duplicates `abs_path` into the same directory as `<name>-copy<ext>`,
  `<name>-copy-2<ext>`, etc. — first name that doesn't already exist.
  """
  def duplicate_file(abs_path) do
    dir = Path.dirname(abs_path)
    ext = Path.extname(abs_path)
    base = Path.basename(abs_path, ext)

    with {:ok, content} <- File.read(abs_path) do
      new_path = unique_copy_path(dir, base, ext, nil)

      case File.write(new_path, content) do
        :ok -> {:ok, new_path}
        error -> error
      end
    end
  end

  @doc "Deletes a single definition file."
  def delete_file(abs_path), do: File.rm(abs_path)

  @doc """
  Shared handler for duplicate_definition_file events.

  Takes a guard function (e.g., `open_path_allowed?/2`) and a reload function
  (e.g., `load_agents/1`) to eliminate boilerplate across LiveViews.
  """
  def handle_duplicate(path, socket, guard_fn, reload_fn) do
    if guard_fn.(path, socket) do
      case duplicate_file(path) do
        {:ok, _new_path} ->
          {:noreply, reload_fn.(socket) |> Phoenix.LiveView.put_flash(:info, "Duplicated")}

        {:error, _} ->
          {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Duplicate failed")}
      end
    else
      {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Path not allowed")}
    end
  end

  @doc """
  Shared handler for delete_definition_file events.

  Takes a guard function (e.g., `open_path_allowed?/2`), a reload function
  (e.g., `load_agents/1`), and an optional clear function to clean up selected
  state (e.g., `&maybe_clear_selected(&1, path)`).
  """
  def handle_delete(path, socket, guard_fn, reload_fn, clear_fn \\ &Function.identity/1) do
    if guard_fn.(path, socket) do
      case delete_file(path) do
        :ok ->
          {:noreply,
           socket
           |> reload_fn.()
           |> clear_fn.()
           |> Phoenix.LiveView.put_flash(:info, "Deleted")}

        {:error, _} ->
          {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Delete failed")}
      end
    else
      {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Path not allowed")}
    end
  end

  defp unique_copy_path(dir, base, ext, n) do
    suffix = if n, do: "-copy-#{n}", else: "-copy"
    candidate = Path.join(dir, "#{base}#{suffix}#{ext}")

    if File.exists?(candidate) do
      unique_copy_path(dir, base, ext, (n || 1) + 1)
    else
      candidate
    end
  end
end
