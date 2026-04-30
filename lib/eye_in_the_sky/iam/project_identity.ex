defmodule EyeInTheSky.IAM.ProjectIdentity do
  @moduledoc """
  Resolves canonical project identity for IAM context construction.

  `project_id` is the canonical authorization identity. `project_path` is a
  fallback-grade string used when a DB-backed project cannot be resolved, or
  for cross-project path-glob rules in policies.

  ## `canonicalize/1` guarantees

    * Input is converted to an absolute path via `Path.expand/1`.
    * A symlink in the *final* path segment is resolved once via
      `:file.read_link/1`. Mid-path symlinks are NOT recursively resolved.
      Callers needing full resolution should pre-resolve via shell `realpath`.
    * Path separators are normalized to `/` (POSIX only in v1).
    * Trailing slash is stripped except for the root `/`.
    * Case is preserved as-is. macOS case-insensitive filesystems are NOT
      normalized — this is a documented limitation.

  Non-goals (v1): Windows paths, recursive symlink resolution through every
  segment, UNC / mount-point awareness.
  """

  require Logger

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Projects.Project
  alias EyeInTheSky.Sessions

  @typedoc """
  Result of `resolve/1`: both fields may be populated (preferred) or just the
  path when no DB project matches.
  """
  @type resolved :: %{project_id: integer() | nil, project_path: String.t() | nil}

  @doc """
  Resolve a raw hook payload's project identity.

  Accepts a map with any of `:session_uuid`, `:cwd`, `"session_id"`, `"cwd"`.
  Prefers the session's linked project; falls back to canonicalizing `cwd`
  and looking it up by path.
  """
  @spec resolve(map()) :: resolved()
  def resolve(payload) when is_map(payload) do
    session_uuid = payload[:session_uuid] || payload["session_id"]
    raw_cwd = payload[:cwd] || payload["cwd"]

    canonical_path = canonicalize(raw_cwd)

    case resolve_from_session(session_uuid) do
      %Project{id: id, path: path} ->
        %{project_id: id, project_path: canonicalize(path) || canonical_path}

      nil ->
        %{project_id: project_id_from_path(canonical_path), project_path: canonical_path}
    end
  end

  @doc """
  Canonicalize a filesystem path string. Returns `nil` for `nil` / non-string
  inputs. See module doc for guarantees.
  """
  @spec canonicalize(String.t() | nil) :: String.t() | nil
  def canonicalize(nil), do: nil
  def canonicalize(""), do: nil

  def canonicalize(path) when is_binary(path) do
    path
    |> Path.expand()
    |> resolve_final_symlink()
    |> normalize_separators()
    |> strip_trailing_slash()
  end

  def canonicalize(_), do: nil

  # ── private ─────────────────────────────────────────────────────────────────

  defp resolve_from_session(nil), do: nil

  defp resolve_from_session(ref) when is_binary(ref) or is_integer(ref) do
    with {:ok, session} <- Sessions.resolve(ref),
         project_id when is_integer(project_id) <- Map.get(session, :project_id),
         {:ok, %Project{} = project} <- Projects.get_project(project_id) do
      project
    else
      _ -> nil
    end
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning("IAM.ProjectIdentity: DB error resolving session #{ref}: #{inspect(e)}")
      nil
  end

  defp resolve_from_session(_), do: nil

  defp project_id_from_path(nil), do: nil

  defp project_id_from_path(path) do
    case Projects.get_project_by_path(path) do
      {:ok, %Project{id: id}} -> id
      _ -> nil
    end
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning("IAM.ProjectIdentity: DB error resolving path #{path}: #{inspect(e)}")
      nil
  end

  defp resolve_final_symlink(path) do
    case :file.read_link(path) do
      {:ok, target} ->
        target_str = to_string(target)

        if Path.type(target_str) == :absolute do
          target_str
        else
          Path.expand(target_str, Path.dirname(path))
        end

      {:error, _} ->
        path
    end
  end

  defp normalize_separators(path) do
    # POSIX-only for v1; no-op on systems that already use /.
    String.replace(path, "\\", "/")
  end

  defp strip_trailing_slash("/"), do: "/"

  defp strip_trailing_slash(path) when is_binary(path) do
    case String.ends_with?(path, "/") do
      true -> String.trim_trailing(path, "/")
      false -> path
    end
  end
end
