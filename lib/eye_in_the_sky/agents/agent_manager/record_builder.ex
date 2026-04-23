defmodule EyeInTheSky.Agents.AgentManager.RecordBuilder do
  @moduledoc false

  require Logger

  alias EyeInTheSky.{AgentDefinitions, Repo, Sessions}
  alias EyeInTheSky.Agents.Agent
  alias EyeInTheSky.Git.Worktrees
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Utils.ToolHelpers

  @doc """
  Creates agent and session records in the database.
  """
  def create_records(opts) do
    agent_uuid = Ecto.UUID.generate()
    provider = resolve_provider(opts)
    session_uuid = resolve_session_uuid(provider, opts)
    description = resolve_description(opts)
    project_id = resolve_project_id(opts)

    Logger.info(
      "📝 create_agent: agent_uuid=#{agent_uuid}, session_uuid=#{inspect(session_uuid)}, model=#{opts[:model]}, project_id=#{project_id}"
    )

    definition_info = resolve_agent_definition(opts[:agent], project_id, opts[:project_path])

    with {:ok, worktree_path} <- resolve_worktree_path(opts) do
      insert_agent_and_session(%{
        agent_uuid: agent_uuid,
        provider: provider,
        session_uuid: session_uuid,
        description: description,
        project_id: project_id,
        worktree_path: worktree_path,
        definition_info: definition_info,
        opts: opts
      })
    end
  end

  defp resolve_provider(opts) do
    case opts[:agent_type] do
      "codex" -> "codex"
      "gemini" -> "gemini"
      _ -> "claude"
    end
  end

  defp resolve_session_uuid(provider, opts) do
    # For codex and gemini sessions, leave uuid null — the provider's native session_id
    # arrives via InitEvent / thread.started and gets synced later via
    # maybe_sync_provider_conversation_id.
    # For claude sessions, pre-generate so the worker can reference it immediately.
    if provider in ["codex", "gemini"],
      do: nil,
      else: opts[:session_uuid] || Ecto.UUID.generate()
  end

  defp resolve_description(opts) do
    opts[:description] || "Agent session"
  end

  defp resolve_project_id(opts) do
    opts[:project_id] ||
      with parent_id when not is_nil(parent_id) <- opts[:parent_session_id],
           {:ok, parent} <- Sessions.get_session(parent_id) do
        parent.project_id
      else
        nil -> nil
        {:error, _} -> nil
      end
  end

  defp resolve_worktree_path(opts) do
    # When a worktree name is given, create the git worktree before DB records.
    # If creation fails, return an error — do NOT silently fall back to the main project path.
    case opts[:worktree] do
      nil ->
        {:ok, opts[:project_path]}

      wt ->
        wt_opts = [stash_if_dirty: opts[:stash_if_dirty] == true]

        case Worktrees.prepare_session_worktree(opts[:project_path], wt, wt_opts) do
          {:ok, _} = ok ->
            ok

          {:error, :dirty_working_tree} = err ->
            Logger.error("create_agent: git worktree setup failed for #{wt}: dirty working tree")
            err

          {:error, reason} ->
            Logger.error("create_agent: git worktree setup failed for #{wt}: #{inspect(reason)}")
            {:error, {:worktree_setup_failed, reason}}
        end
    end
  end

  defp insert_agent_and_session(%{
         agent_uuid: agent_uuid,
         provider: provider,
         session_uuid: session_uuid,
         description: description,
         project_id: project_id,
         worktree_path: worktree_path,
         definition_info: definition_info,
         opts: opts
       }) do
    agent_attrs =
      %{
        uuid: agent_uuid,
        agent_type: opts[:agent_type] || "claude",
        project_id: project_id,
        project_name: opts[:project_name],
        status: "pending",
        description: description,
        git_worktree_path: worktree_path,
        parent_agent_id: opts[:parent_agent_id],
        parent_session_id: opts[:parent_session_id]
      }
      |> maybe_put_definition(definition_info)

    agent_changeset = Agent.changeset(%Agent{}, agent_attrs)

    session_opts = %{
      uuid: session_uuid,
      name: description,
      description: "agent-id #{agent_uuid}",
      model: opts[:model],
      provider: provider,
      project_id: project_id,
      git_worktree_path: worktree_path,
      started_at: DateTime.utc_now(),
      parent_agent_id: opts[:parent_agent_id],
      parent_session_id: opts[:parent_session_id]
    }

    result =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:agent, agent_changeset)
      |> Ecto.Multi.run(:session, fn _repo, %{agent: agent} ->
        Repo.insert(Session.changeset(%Session{}, Map.put(session_opts, :agent_id, agent.id)))
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{agent: agent, session: session}} ->
        EyeInTheSky.Events.agent_created(agent)

        Logger.info(
          "✅ create_agent: DB records created - agent.id=#{agent.id}, session.id=#{session.id}, session_uuid=#{session.uuid}"
        )

        {:ok, %{agent: agent, session: session}}

      {:error, _step, reason, _changes_so_far} ->
        Logger.error("❌ create_agent: DB record creation failed - #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_put_definition(attrs, nil), do: attrs

  defp maybe_put_definition(attrs, definition_info) do
    Map.merge(attrs, definition_info)
  end

  # ── Agent definition resolution ────────────────────────────────────────

  # Resolves an agent slug to a definition record. Returns a map with
  # :agent_definition_id and :definition_checksum_at_spawn, or nil.
  # If the slug is not found in the DB, syncs the relevant directory first and retries.
  defp resolve_agent_definition(nil, _project_id, _project_path), do: nil
  defp resolve_agent_definition("", _project_id, _project_path), do: nil

  defp resolve_agent_definition(slug, project_id, project_path) do
    project_id = ToolHelpers.parse_int(project_id)

    case lookup_definition(slug, project_id) do
      {:ok, defn} ->
        %{agent_definition_id: defn.id, definition_checksum_at_spawn: defn.checksum}

      {:error, :not_found} ->
        Logger.debug("resolve_agent_definition: slug=#{slug} not in DB, syncing and retrying")
        sync_for_spawn(project_id, project_path)

        case lookup_definition(slug, project_id) do
          {:ok, defn} ->
            %{agent_definition_id: defn.id, definition_checksum_at_spawn: defn.checksum}

          {:error, :not_found} ->
            Logger.debug("resolve_agent_definition: slug=#{slug} not found after sync")
            nil
        end
    end
  end

  defp lookup_definition(slug, project_id) do
    if project_id do
      AgentDefinitions.resolve(slug, project_id)
    else
      AgentDefinitions.resolve_global(slug)
    end
  end

  defp sync_for_spawn(nil, _project_path), do: AgentDefinitions.sync_global()

  defp sync_for_spawn(project_id, project_path) do
    AgentDefinitions.sync_global()

    if project_path do
      AgentDefinitions.sync_project(project_id, project_path)
    end
  end
end
