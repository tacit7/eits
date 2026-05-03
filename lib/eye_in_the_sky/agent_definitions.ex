defmodule EyeInTheSky.AgentDefinitions do
  @moduledoc """
  Context for managing agent definition files.

  Catalogs `.md` agent files from global (`~/.claude/agents/`) and
  project-scoped (`.claude/agents/`) directories. Sync reads the filesystem,
  parses frontmatter metadata, and upserts into the `agent_definitions` table.

  ## Resolution order

  When resolving a slug for a given project, project-scoped definitions
  take precedence over global definitions (project override resolution,
  fallback to global).
  """

  import Ecto.Query, warn: false

  alias EyeInTheSky.AgentDefinitions.AgentDefinition
  alias EyeInTheSky.AgentDefinitions.FrontmatterParser
  alias EyeInTheSky.Repo

  @global_agents_dir Path.expand("~/.claude/agents")

  # ── Queries ──────────────────────────────────────────────────────────────

  @doc """
  Lists all non-missing definitions, optionally filtered by project.
  """
  def list_definitions(project_id \\ nil) do
    AgentDefinition
    |> where([d], is_nil(d.missing_at))
    |> maybe_filter_project(project_id)
    |> order_by([d], desc: d.scope, asc: d.slug)
    |> limit(500)
    |> Repo.all()
  end

  @doc """
  Lists definitions available for a given project: project-scoped + global.
  Project definitions first, then global.
  """
  def list_for_project(project_id) do
    AgentDefinition
    |> where([d], is_nil(d.missing_at))
    |> where([d], d.project_id == ^project_id or d.scope == "global")
    |> order_by([d], desc: d.scope, asc: d.slug)
    |> limit(500)
    |> Repo.all()
  end

  @doc """
  Resolves a definition by slug for a given project.
  Project-scoped definitions take precedence over global.
  Returns `{:ok, definition}` or `{:error, :not_found}`.
  """
  def resolve(slug, project_id) do
    result =
      Repo.one(
        from d in AgentDefinition,
          where: d.slug == ^slug and is_nil(d.missing_at),
          where: (d.project_id == ^project_id and d.scope == "project") or d.scope == "global",
          order_by: [desc: d.scope],
          limit: 1
      )

    case result do
      %AgentDefinition{} = defn -> {:ok, defn}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Resolves a definition by slug without project context (global only).
  """
  def resolve_global(slug) do
    case Repo.one(
           from d in AgentDefinition,
             where: d.slug == ^slug and d.scope == "global" and is_nil(d.missing_at)
         ) do
      %AgentDefinition{} = defn -> {:ok, defn}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets a single definition by ID.
  """
  def get_definition(id) do
    case Repo.get(AgentDefinition, id) do
      nil -> {:error, :not_found}
      defn -> {:ok, defn}
    end
  end

  # ── Sync ─────────────────────────────────────────────────────────────────

  @doc """
  Syncs global agent definitions from `~/.claude/agents/`.
  """
  def sync_global do
    sync_directory(@global_agents_dir, "global", nil)
  end

  @doc """
  Syncs project-scoped agent definitions from `<project_path>/.claude/agents/`.
  """
  def sync_project(%{id: project_id, path: project_path}) do
    dir = Path.join(project_path, ".claude/agents")
    sync_directory(dir, "project", project_id)
  end

  def sync_project(project_id, project_path) do
    dir = Path.join(project_path, ".claude/agents")
    sync_directory(dir, "project", project_id)
  end

  @doc false
  # Test-only: allows passing an explicit directory path rather than deriving from project_path.
  if Mix.env() == :test do
    def sync_directory_for_test(dir, scope, project_id) do
      sync_directory(dir, scope, project_id)
    end
  end

  defp sync_directory(dir, scope, project_id) do
    lock_key = sync_lock_key(scope, project_id)

    Repo.transaction(fn ->
      # Advisory lock prevents concurrent syncs for the same scope/project from racing
      Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])
      now = DateTime.utc_now()
      sync_directory_contents(dir, scope, project_id, now)
    end)
  end

  defp sync_directory_contents(dir, scope, project_id, now) do
    if File.dir?(dir) do
      md_files =
        dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.reject(&(&1 == "README.md"))

      # Pre-fetch all existing definitions for this scope/project in one query to
      # avoid an N+1 SELECT inside the Enum.map below.
      existing_map = fetch_existing_map(scope, project_id)

      ctx = %{scope: scope, project_id: project_id, now: now, existing_map: existing_map}

      synced_slugs =
        Enum.map(md_files, fn filename ->
          sync_file(Path.join(dir, filename), Path.rootname(filename), ctx)
        end)
        |> Enum.reject(&is_nil/1)

      mark_missing(scope, project_id, synced_slugs, now)
      synced_slugs
    else
      # Directory absent — mark all existing definitions for this scope as missing
      mark_missing(scope, project_id, [], now)
      []
    end
  end

  # Returns a %{slug => AgentDefinition} map for all existing definitions in scope.
  defp fetch_existing_map("global", _project_id) do
    from(d in AgentDefinition, where: d.scope == "global")
    |> Repo.all()
    |> Map.new(&{&1.slug, &1})
  end

  defp fetch_existing_map("project", project_id) do
    from(d in AgentDefinition, where: d.scope == "project" and d.project_id == ^project_id)
    |> Repo.all()
    |> Map.new(&{&1.slug, &1})
  end

  defp sync_file(file_path, slug, %{scope: _, project_id: _, now: _, existing_map: _} = ctx) do
    case sync_one(file_path, slug, ctx) do
      {:ok, _defn} -> slug
      {:error, _reason} -> nil
    end
  end

  # Deterministic advisory lock key from scope + project_id.
  # Uses Erlang's phash2 which returns a 32-bit integer — fits pg_advisory_xact_lock's bigint param.
  defp sync_lock_key(scope, project_id) do
    :erlang.phash2({:agent_def_sync, scope, project_id})
  end

  defp sync_one(file_path, slug, %{scope: scope, project_id: project_id, now: now, existing_map: existing_map}) do
    case File.read(file_path) do
      {:error, _} -> {:error, :missing}
      {:ok, content} -> sync_one_content(file_path, content, slug, %{scope: scope, project_id: project_id, now: now, existing_map: existing_map})
    end
  end

  defp sync_one_content(file_path, content, slug, %{scope: scope, project_id: project_id, now: now, existing_map: existing_map}) do
    checksum = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    existing = Map.get(existing_map, slug)

    case existing do
      %AgentDefinition{checksum: ^checksum} = defn ->
        defn
        |> AgentDefinition.changeset(%{last_synced_at: now, missing_at: nil})
        |> Repo.update()

      %AgentDefinition{} = defn ->
        metadata = parse_frontmatter(content)

        defn
        |> AgentDefinition.changeset(
          Map.merge(metadata, %{checksum: checksum, last_synced_at: now, missing_at: nil})
        )
        |> Repo.update()

      nil ->
        metadata = parse_frontmatter(content)
        stored_path = stored_path(file_path, scope)

        %AgentDefinition{}
        |> AgentDefinition.changeset(
          Map.merge(metadata, %{
            slug: slug,
            scope: scope,
            project_id: project_id,
            path: stored_path,
            checksum: checksum,
            last_synced_at: now
          })
        )
        |> Repo.insert()
    end
  end

  defp mark_missing(scope, project_id, synced_slugs, now) do
    query =
      from d in AgentDefinition,
        where: d.scope == ^scope and is_nil(d.missing_at)

    query =
      if project_id do
        where(query, [d], d.project_id == ^project_id)
      else
        where(query, [d], is_nil(d.project_id))
      end

    query =
      if synced_slugs != [] do
        where(query, [d], d.slug not in ^synced_slugs)
      else
        query
      end

    Repo.update_all(query, set: [missing_at: now])
  end

  # ── Path semantics ──────────────────────────────────────────────────────

  defp stored_path(file_path, "global"), do: file_path

  defp stored_path(file_path, "project") do
    case Regex.run(~r{(\.claude/agents/.+)$}, file_path) do
      [_, relative] -> relative
      _ -> file_path
    end
  end

  @doc """
  Returns the absolute path for a definition, resolving project-relative paths.
  """
  def absolute_path(%AgentDefinition{scope: "global", path: path}), do: path

  def absolute_path(%AgentDefinition{scope: "project", path: path, project_id: project_id}) do
    case EyeInTheSky.Projects.get_project(project_id) do
      {:ok, project} -> Path.join(project.path, path)
      {:error, :not_found} -> path
    end
  end

  # ── Frontmatter parsing ────────────────────────────────────────────────

  def parse_frontmatter(content), do: FrontmatterParser.parse_frontmatter(content)

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp maybe_filter_project(query, nil), do: query

  defp maybe_filter_project(query, project_id) do
    where(query, [d], d.project_id == ^project_id or d.scope == "global")
  end
end
