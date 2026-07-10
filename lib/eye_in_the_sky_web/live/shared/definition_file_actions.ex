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
