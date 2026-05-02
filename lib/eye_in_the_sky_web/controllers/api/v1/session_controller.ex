defmodule EyeInTheSkyWeb.Api.V1.SessionController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  require Logger

  alias EyeInTheSky.{Agents, Commits, Contexts, Notes, Projects, Sessions, Tasks}
  alias EyeInTheSky.Utils.ToolHelpers, as: Helpers
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  POST /api/v1/sessions - Register a new session (SessionStart hook).

  Creates an Agent (identity) and a Session (execution session).
  Mirrors the i-start-session MCP tool flow.
  """
  def create(conn, params) do
    session_uuid = params["session_id"]

    if is_nil(session_uuid) or session_uuid == "" do
      {:error, :bad_request, "session_id is required"}
    else
      case Projects.resolve_project(params) do
        {:ok, project_id, _name} ->
          case Sessions.get_session_by_uuid(session_uuid) do
            {:ok, existing} -> handle_session_resume(conn, existing, params)
            {:error, :not_found} -> handle_new_session(conn, params, project_id)
          end

        {:error, _code, message} ->
          {:error, message}
      end
    end
  end

  defp handle_session_resume(conn, session, params) do
    update_attrs =
      %{status: "working", last_activity_at: DateTime.utc_now()}
      |> Helpers.maybe_put(:name, params["name"])
      |> Helpers.maybe_put(:description, params["description"])

    case Sessions.update_session(session, update_attrs) do
      {:ok, updated} ->
        EyeInTheSky.Events.session_updated(updated)

        agent_uuid = Helpers.resolve_agent_uuid(updated.agent_id)

        json(conn, %{
          id: updated.id,
          uuid: updated.uuid,
          agent_id: updated.agent_id,
          agent_uuid: agent_uuid,
          project_id: updated.project_id,
          status: updated.status
        })

      {:error, _changeset} ->
        {:error, "Failed to update session"}
    end
  end

  defp handle_new_session(conn, params, project_id) do
    case Sessions.register_from_hook(params, project_id) do
      {:ok, %{session: session, agent: agent}} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: session.id,
          uuid: session.uuid,
          agent_id: agent.id,
          agent_uuid: agent.uuid,
          status: session.status
        })

      {:error, :agent, _changeset} ->
        {:error, "Failed to create agent"}

      {:error, :session, _changeset} ->
        {:error, "Failed to create session"}
    end
  end

  @doc """
  PATCH /api/v1/sessions/:uuid - Update session status (SessionEnd, Stop, Compact hooks).
  """
  def update(conn, %{"uuid" => uuid} = params) do
    with {:ok, session} <- resolve_session(uuid) do
      attrs = build_update_attrs(params)

      case Sessions.update_session(session, attrs) do
        {:ok, updated} ->
          trigger_status_side_effects(updated, params["status"])

          json(conn, %{
            id: updated.id,
            uuid: updated.uuid,
            status: updated.status,
            ended_at: updated.ended_at
          })

        {:error, _changeset} ->
          {:error, "Failed to update session"}
      end
    else
      {:error, :not_found} -> {:error, :not_found, "Session not found"}
    end
  end

  defp build_update_attrs(params) do
    status = params["status"]

    %{}
    |> Helpers.maybe_put(:status, status)
    |> Helpers.maybe_put(:status_reason, params["status_reason"])
    |> Helpers.maybe_put(:intent, params["intent"])
    |> maybe_put_read_only(params["read_only"])
    |> Helpers.maybe_put(:entrypoint, params["entrypoint"])
    |> Helpers.maybe_put(:name, params["name"])
    |> Helpers.maybe_put(:description, params["description"])
    |> Helpers.maybe_put(:project_id, parse_int(params["project_id"], nil))
    |> Helpers.maybe_put(:last_activity_at, DateTime.utc_now())
    |> then(fn a ->
      if params["clear_entrypoint"] in [true, "true"], do: Map.put(a, :entrypoint, nil), else: a
    end)
    |> then(fn a ->
      if status && status != "waiting" && !params["status_reason"],
        do: Map.put(a, :status_reason, nil), else: a
    end)
    |> then(fn a ->
      if status in Sessions.terminated_statuses(),
        do: Map.put(a, :ended_at, params["ended_at"] || DateTime.utc_now()), else: a
    end)
  end

  @doc """
  POST /api/v1/sessions/:uuid/tool-events - Record a tool pre/post event.

  Body: type ("pre" | "post"), tool_name, tool_input (optional)
  Writes a Message record and broadcasts PubSub events for DmLive real-time UI.
  """
  def tool_event(conn, %{"uuid" => uuid} = params) do
    tool_name = params["tool_name"]

    if is_nil(tool_name) or tool_name == "" do
      {:error, :bad_request, "tool_name is required"}
    else
      with {:ok, session} <- resolve_session(uuid) do
        Sessions.update_session(session, %{last_activity_at: DateTime.utc_now()})
        Sessions.record_tool_event(session, params["type"], params)
        json(conn, %{success: true})
      else
        {:error, :not_found} -> {:error, :not_found, "Session not found"}
      end
    end
  end

  @doc """
  GET /api/v1/sessions - Search sessions.
  Query params: q, limit (default 20)
  """
  def index(conn, params) do
    opts = build_session_filter_opts(params)
    results = Sessions.list_sessions_filtered(opts)

    with_tasks = params["with_tasks"] in ["true", "1", true]

    sessions_data =
      if with_tasks do
        session_ids = Enum.map(results, & &1.id)
        tasks_by_session = Tasks.list_tasks_for_sessions(session_ids)

        Enum.map(results, fn s ->
          task_list =
            tasks_by_session
            |> Map.get(s.id, [])
            |> Enum.map(fn t ->
              %{id: t.id, title: t.title, state_id: t.state_id,
                state: if(t.state, do: t.state.name, else: nil)}
            end)

          Map.put(ApiPresenter.present_session(s), :tasks, task_list)
        end)
      else
        Enum.map(results, &ApiPresenter.present_session/1)
      end

    json(conn, %{
      success: true,
      message: "Found #{length(results)} session(s)",
      results: sessions_data
    })
  end

  @doc """
  GET /api/v1/sessions/:uuid - Get session info.
  Accepts UUID string or integer session ID.
  """
  def show(conn, %{"uuid" => id_or_uuid}) do
    with {:ok, session} <- resolve_session(id_or_uuid) do
      agent_uuid = Helpers.resolve_agent_uuid(session.agent_id)

      is_spawned =
        case Agents.get_agent(session.agent_id) do
          {:ok, agent} -> not is_nil(agent.parent_agent_id)
          _ -> false
        end

      tasks = Tasks.list_tasks_for_session(session.id)
      notes = Notes.list_notes_for_session(session.id, limit: 5)
      commits = Commits.list_commits_for_session(session.id, limit: 5)
      branch_name = resolve_branch_name(session.git_worktree_path)

      json(
        conn,
        ApiPresenter.present_session_detail(session,
          agent_uuid: agent_uuid,
          is_spawned: is_spawned,
          tasks: tasks,
          recent_notes: notes,
          recent_commits: commits,
          worktree_path: session.git_worktree_path,
          branch_name: branch_name
        )
      )
    else
      {:error, :not_found} -> {:error, :not_found, "Session not found"}
    end
  end

  @doc """
  POST /api/v1/sessions/:id/complete - Mark session completed; syncs team member to "done".
  Accepts integer session ID or UUID string.
  """
  def complete(conn, %{"uuid" => id_or_uuid}) do
    with {:ok, session} <- resolve_session(id_or_uuid) do
      attrs = %{status: "completed", ended_at: DateTime.utc_now()}

      do_session_status_change(conn, session, attrs, fn updated ->
        EyeInTheSky.Events.session_completed(updated)
        EyeInTheSky.Events.session_updated(updated)
        sync_member_status(updated.id, "done")
      end)
    else
      {:error, :not_found} -> {:error, :not_found, "Session not found"}
    end
  end

  @doc """
  POST /api/v1/sessions/:uuid/reopen - Reopen a completed or failed session.
  Clears ended_at and sets status to idle so the session can accept new task
  updates and DMs. Useful when a resume hook fails to reset status, or when
  an orchestrator needs to post work against an already-ended session.
  Accepts integer session ID or UUID string.
  """
  def reopen(conn, %{"uuid" => id_or_uuid}) do
    with {:ok, session} <- resolve_session(id_or_uuid) do
      attrs = %{status: "idle", ended_at: nil}

      do_session_status_change(conn, session, attrs, fn updated ->
        EyeInTheSky.Events.session_updated(updated)
        false
      end)
    else
      {:error, :not_found} -> {:error, :not_found, "Session not found"}
    end
  end

  @doc """
  POST /api/v1/sessions/:id/waiting - Mark session waiting; syncs team member to "blocked".
  Accepts integer session ID or UUID string.
  """
  def waiting(conn, %{"uuid" => id_or_uuid}) do
    with {:ok, session} <- resolve_session(id_or_uuid) do
      attrs = %{status: "waiting"}

      do_session_status_change(conn, session, attrs, fn updated ->
        EyeInTheSky.Events.agent_stopped(updated)
        EyeInTheSky.Events.session_updated(updated)
        sync_member_status(updated.id, "blocked")
      end)
    else
      {:error, :not_found} -> {:error, :not_found, "Session not found"}
    end
  end

  defp sync_member_status(session_id, member_status) do
    EyeInTheSky.Teams.mark_member_done_by_session(session_id, member_status) > 0
  rescue
    e ->
      Logger.warning(
        "sync_member_status failed for session #{session_id}: #{inspect(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )
      false
  end

  defp do_session_status_change(conn, session, attrs, side_effects_fn) do
    case Sessions.update_session(session, attrs) do
      {:ok, updated} ->
        member_synced = side_effects_fn.(updated)

        json(conn, %{
          success: true,
          session_id: updated.id,
          session_status: updated.status,
          member_synced: member_synced
        })

      {:error, _cs} ->
        {:error, "Failed to update session"}
    end
  end

  defp resolve_session(id_or_uuid), do: Sessions.resolve(id_or_uuid)

  @doc """
  POST /api/v1/sessions/:uuid/end - End a session with optional summary and final status.
  """
  def end_session(conn, %{"uuid" => uuid} = params) do
    with {:ok, session} <- resolve_session(uuid) do
      status = params["final_status"] || "completed"

      attrs =
        if status in Sessions.terminated_statuses() do
          %{status: status, ended_at: DateTime.utc_now()}
        else
          %{status: status}
        end

      case Sessions.update_session(session, attrs) do
        {:ok, updated} ->
          handle_terminal_status(updated, status)
          json(conn, %{success: true, message: "Session ended", status: updated.status})

        {:error, _cs} ->
          {:error, "Failed"}
      end
    else
      {:error, :not_found} -> {:error, :not_found, "Session not found"}
    end
  end

  @doc """
  POST /api/v1/sessions/:uuid/archive - Archive a session.
  """
  def archive(conn, %{"uuid" => uuid}) do
    with {:ok, session} <- resolve_session(uuid) do
      case Sessions.archive_session(session) do
        {:ok, updated} ->
          json(conn, %{success: true, uuid: updated.uuid, archived: true})

        {:error, _} ->
          {:error, "Failed to archive session"}
      end
    else
      {:error, :not_found} -> {:error, :not_found, "Session not found"}
    end
  end

  @doc """
  POST /api/v1/sessions/:uuid/unarchive - Unarchive a session.
  """
  def unarchive(conn, %{"uuid" => uuid}) do
    with {:ok, session} <- resolve_session(uuid) do
      case Sessions.unarchive_session(session) do
        {:ok, updated} ->
          json(conn, %{success: true, uuid: updated.uuid, archived: false})

        {:error, _} ->
          {:error, "Failed to unarchive session"}
      end
    else
      {:error, :not_found} -> {:error, :not_found, "Session not found"}
    end
  end

  @doc """
  GET /api/v1/sessions/:uuid/context - Load session context.
  """
  def get_context(conn, %{"uuid" => uuid}) do
    with {:ok, session} <- resolve_session(uuid) do
      case Contexts.get_session_context(session.id) do
        {:error, :not_found} ->
          {:error, :not_found, "No context found"}

        {:ok, ctx} ->
          json(conn, %{
            success: true,
            context: ctx.context,
            metadata: ctx.metadata,
            updated_at: to_string(ctx.updated_at)
          })
      end
    else
      {:error, :not_found} -> {:error, :not_found, "Session not found"}
    end
  end

  @doc """
  PATCH /api/v1/sessions/:uuid/context - Save/update session context.
  """
  def update_context(conn, %{"uuid" => uuid} = params) do
    context = params["context"]

    if is_nil(context) or context == "" do
      {:error, :bad_request, "context is required"}
    else
      metadata = normalize_metadata(params["metadata"])

      with {:ok, session} <- resolve_session(uuid) do
        do_upsert_context(conn, session, context, metadata)
      else
        {:error, :not_found} -> {:error, :not_found, "Session not found"}
      end
    end
  end

  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata(m) when is_map(m), do: m
  defp normalize_metadata(s) when is_binary(s) do
    case Jason.decode(s) do
      {:ok, m} when is_map(m) -> m
      _ -> %{}
    end
  end
  defp normalize_metadata(_), do: %{}

  defp do_upsert_context(conn, session, context, metadata) do
    attrs = %{agent_id: session.agent_id, session_id: session.id, context: context, metadata: metadata}

    case Contexts.upsert_session_context(attrs) do
      {:ok, sc} ->
        json(conn, %{success: true, context: sc.context, metadata: sc.metadata})

      {:error, _cs} ->
        {:error, "Failed"}
    end
  end

  defp trigger_status_side_effects(updated, status) do
    if status do
      if status in ["completed", "failed", "waiting", "idle"] do
        EyeInTheSky.Events.agent_stopped(updated)
      else
        EyeInTheSky.Events.agent_working(updated)
      end
    end

    EyeInTheSky.Events.session_updated(updated)

    if status in Sessions.terminated_statuses() do
      handle_terminal_status(updated, status)
    end
  end

  defp handle_terminal_status(session, status) do
    member_status = if status == "failed", do: "failed", else: "done"
    EyeInTheSky.Teams.mark_member_done_by_session(session.id, member_status)
  end

  defp resolve_branch_name(nil), do: nil

  defp resolve_branch_name(wt_path) do
    case System.cmd("git", ["-C", wt_path, "symbolic-ref", "--short", "HEAD"],
           stderr_to_stdout: true
         ) do
      {branch, 0} -> String.trim(branch)
      _ -> nil
    end
  end

  defp maybe_put_read_only(attrs, nil), do: attrs
  defp maybe_put_read_only(attrs, ""), do: attrs
  defp maybe_put_read_only(attrs, val) when val in [true, "true", "1", 1], do: Map.put(attrs, :read_only, true)
  defp maybe_put_read_only(attrs, val) when val in [false, "false", "0", 0], do: Map.put(attrs, :read_only, false)
  defp maybe_put_read_only(attrs, _), do: attrs

  defp maybe_put_session_opt(opts, _key, nil), do: opts
  defp maybe_put_session_opt(opts, _key, false), do: opts
  defp maybe_put_session_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp build_session_filter_opts(params) do
    agent_int_id =
      if params["agent_id"], do: resolve_agent_int_id(params["agent_id"]), else: nil

    parent_session_int_id =
      if params["parent_session_id"] do
        case Sessions.resolve(params["parent_session_id"]) do
          {:ok, s} -> s.id
          _ -> nil
        end
      end

    include_archived = params["include_archived"] in ["true", "1", true]
    name = if params["name"] && params["name"] != "", do: params["name"]

    [search_query: params["q"] || ""]
    |> maybe_put_session_opt(:project_id, params["project_id"] && parse_int(params["project_id"], nil))
    |> maybe_put_session_opt(:status_filter, params["status"])
    |> maybe_put_session_opt(:agent_id, agent_int_id)
    |> maybe_put_session_opt(:parent_session_id, parent_session_int_id)
    |> maybe_put_session_opt(:include_archived, include_archived && true)
    |> maybe_put_session_opt(:name_filter, name)
    |> Keyword.put(:limit, parse_int(params["limit"], 20))
  end

end
