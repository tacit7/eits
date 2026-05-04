defmodule EyeInTheSky.IAM.Builtin.BlockReadOutsideCwd do
  @moduledoc """
  Deny Read/Glob/Grep and Bash file reads whose resolved absolute path
  falls outside the project's cwd (i.e., `Context.project_path`).

  Resolution strategy:

    * Expand the path relative to cwd (`Path.expand/2`).
    * Walk to the deepest existing ancestor and resolve symlinks there
      via `:file.read_link_all/1` so an in-cwd symlink pointing at
      `/etc` cannot escape the check.
    * Compare the resolved absolute path to the resolved cwd with a
      directory-boundary prefix check (trailing `/`).

  Paths that cannot be resolved (no `project_path`) do not match — fail
  closed in the sense of "does not match," not "deny."
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @impl true
  def matches?(%Policy{} = _p, %Context{project_path: cwd} = ctx)
      when is_binary(cwd) do
    case extract_path(ctx) do
      nil -> false
      path -> outside?(path, cwd)
    end
  end

  def matches?(_, _), do: false

  defp extract_path(%Context{tool: tool, resource_path: path})
       when tool in ~w(Read Glob Grep) and is_binary(path),
       do: path

  defp extract_path(%Context{tool: "Bash", resource_content: cmd}) when is_binary(cmd) do
    # Naive extraction: first absolute path or ~-prefixed token.
    # Does not attempt to parse every shell form — built-in is advisory
    # alongside the stricter per-tool policies.
    #
    # Guard: reject candidates whose first path segment does not exist on the
    # filesystem. This filters URL-like strings such as `/api/v1/foo` that
    # appear inside --message / --body / --instructions argument values —
    # those are not filesystem paths and would otherwise produce false-positive
    # denies for CLI tools like `eits dm`.
    case Regex.run(~r/(?:^|\s)((?:~|\/)[^\s;&|`<>]+)/, cmd) do
      [_, p] -> if filesystem_path?(p), do: p, else: nil
      _ -> nil
    end
  end

  defp extract_path(_), do: nil

  # Returns true when the first segment of `path` exists in the local
  # filesystem, indicating the candidate is a real path rather than a
  # URL route string.
  defp filesystem_path?("~" <> _ = path) do
    case System.user_home() do
      nil -> false
      home -> File.exists?(home) and filesystem_path?(Path.expand(path))
    end
  end

  defp filesystem_path?("/" <> _ = path) do
    first_segment =
      path
      |> String.trim_leading("/")
      |> String.split("/")
      |> List.first("")

    File.exists?("/" <> first_segment)
  end

  defp filesystem_path?(_), do: false

  defp outside?(path, cwd) do
    abs = path |> expand_with_home(cwd) |> resolve_symlinks()
    root = cwd |> Path.expand() |> resolve_symlinks()
    not (abs == root or String.starts_with?(abs, root <> "/"))
  end

  defp expand_with_home("~" <> rest, cwd) do
    case System.user_home() do
      nil -> Path.expand("~" <> rest, cwd)
      home -> Path.expand(home <> rest)
    end
  end

  defp expand_with_home(path, cwd), do: Path.expand(path, cwd)

  # Resolve all symlinks along the deepest existing prefix of `path`, then
  # reattach any non-existent tail. This blocks symlink-based escapes
  # (`cwd/link -> /etc`) while still allowing paths that don't exist yet
  # (e.g. a planned Write target) to be evaluated.
  defp resolve_symlinks(path) do
    {resolved_head, tail} = deepest_existing(path, [])

    head =
      case :file.read_link_all(String.to_charlist(resolved_head)) do
        {:ok, chars} -> List.to_string(chars)
        {:error, _} -> resolved_head
      end

    case tail do
      [] -> head
      parts -> Path.join([head | parts])
    end
  end

  defp deepest_existing(path, acc) do
    if path_exists?(path) do
      {path, acc}
    else
      parent = Path.dirname(path)

      if parent == path,
        do: {path, acc},
        else: deepest_existing(parent, [Path.basename(path) | acc])
    end
  end

  defp path_exists?(path) do
    File.exists?(path) or File.lstat(path) != {:error, :enoent}
  end
end
