defmodule EyeInTheSkyWeb.Api.V1.SessionController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, Contexts, Sessions, Projects}
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
      conn |> put_status(:bad_request) |> json(%{error: "session_id is required"})
    else
      project_id =
        case Projects.resolve_project(params) do
          {:ok, id, _name} -> id
          {:error, _, _} -> nil
        end

      case Sessions.get_session_by_uuid(session_uuid) do
        {:ok, existing} -> handle_session_resume(conn, existing, params)
        {:error, :not_found} -> handle_new_session(conn, params, project_id)
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
        json(conn, %{id: updated.id, uuid: updated.uuid, agent_id: nil, agent_uuid: nil, status: updated.status})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to update session", details: translate_errors(changeset)})
    end
  end

  defp handle_new_session(conn, params, project_id) do
    session_uuid = params["session_id"]

    agent_attrs = %{
      uuid: params["agent_id"] || session_uuid,
      description: params["agent_description"] || params["description"],
      project_id: project_id,
      project_name: params["project_name"],
      git_worktree_path: params["worktree_path"],
      source: "hook"
    }

    with {:ok, agent} <- Agents.find_or_create_agent(agent_attrs) do
      {model_provider, model_name} = Sessions.ModelInfo.parse_model_string(params["model"])

      session_attrs = %{
        uuid: session_uuid,
        agent_id: agent.id,
        name: params["name"],
        description: params["description"],
        status: "working",
        started_at: DateTime.utc_now(),
        provider: params["provider"] || "claude",
        model: params["model"],
        model_provider: model_provider,
        model_name: model_name,
        project_id: project_id,
        git_worktree_path: params["worktree_path"],
        entrypoint: params["entrypoint"]
      }

      create_fn =
        if model_name,
          do: &Sessions.create_session_with_model/1,
          else: &Sessions.create_session/1

      case create_fn.(session_attrs) do
        {:ok, session} ->
          EyeInTheSky.Events.session_started(session)

          conn
          |> put_status(:created)
          |> json(%{
            id: session.id,
            uuid: session.uuid,
            agent_id: agent.id,
            agent_uuid: agent.uuid,
            status: session.status
          })

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to create session", details: translate_errors(changeset)})
      end
    else
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create agent", details: translate_errors(changeset)})
    end
  end

  @doc """
  PATCH /api/v1/sessions/:uuid - Update session status (SessionEnd, Stop, Compact hooks).
  """
  def update(conn, %{"uuid" => uuid} = params) do
    case Sessions.get_session_by_uuid(uuid) do
      {:ok, session} ->
        status = params["status"]

        attrs =
          %{}
          |> Helpers.maybe_put(:status, status)
          |> Helpers.maybe_put(:intent, params["intent"])
          |> Helpers.maybe_put(:entrypoint, params["entrypoint"])
          |> Helpers.maybe_put(:name, params["name"])
          |> Helpers.maybe_put(:description, params["description"])
          |> Helpers.maybe_put(:last_activity_at, DateTime.utc_now())

        # Explicit entrypoint clear — set to nil so LiveView removes the CLI icon
        attrs =
          if params["clear_entrypoint"] do
            Map.put(attrs, :entrypoint, nil)
          else
            attrs
          end

        # For terminal states, set ended_at
        attrs =
          if status in ["completed", "failed"] do
            Map.put(
              attrs,
              :ended_at,
              params["ended_at"] || DateTime.utc_now()
            )
          else
            attrs
          end

        case Sessions.update_session(session, attrs) do
          {:ok, updated} ->
            trigger_status_side_effects(updated, status)

            json(conn, %{
              id: updated.id,
              uuid: updated.uuid,
              status: updated.status,
              ended_at: updated.ended_at
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to update session", details: translate_errors(changeset)})
        end

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Session not found"})
    end
  end

  @doc """
  POST /api/v1/sessions/:uuid/tool-events - Record a tool pre/post event.

  Body: type ("pre" | "post"), tool_name, tool_input (optional)
  Writes a Message record and broadcasts PubSub events for DmLive real-time UI.
  """
  def tool_event(conn, %{"uuid" => uuid} = params) do
    type = params["type"]
    tool_name = params["tool_name"]

    if is_nil(tool_name) or tool_name == "" do
      conn |> put_status(:bad_request) |> json(%{error: "tool_name is required"})
    else
      case Sessions.get_session_by_uuid(uuid) do
        {:ok, session} ->
          Sessions.update_session(session, %{
            last_activity_at: DateTime.utc_now()
          })

          Sessions.record_tool_event(session, type, params)
          json(conn, %{success: true})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "Session not found"})
      end
    end
  end

  @doc """
  GET /api/v1/sessions - Search sessions.
  Query params: q, limit (default 20)
  """
  def index(conn, params) do
    query = params["q"] || ""
    limit = parse_int(params["limit"], 20)

    opts = [search_query: query]

    opts =
      if params["project_id"],
        do: Keyword.put(opts, :project_id, parse_int(params["project_id"], nil)),
        else: opts

    opts =
      if params["status"], do: Keyword.put(opts, :status_filter, params["status"]), else: opts

    results = Sessions.list_sessions_filtered(opts) |> Enum.take(limit)

    json(conn, %{
      success: true,
      message: "Found #{length(results)} session(s)",
      results: Enum.map(results, &ApiPresenter.present_session/1)
    })
  end

  @doc """
  GET /api/v1/sessions/:uuid - Get session info.
  Accepts UUID string or integer session ID.
  """
  def show(conn, %{"uuid" => id_or_uuid}) do
    case resolve_session(id_or_uuid) do
      {:ok, session} ->
        agent_uuid = Helpers.resolve_agent_uuid(session.agent_id)

        is_spawned =
          case Agents.get_agent(session.agent_id) do
            {:ok, agent} -> not is_nil(agent.parent_agent_id)
            _ -> false
          end

        json(conn, ApiPresenter.present_session_detail(session, agent_uuid: agent_uuid, is_spawned: is_spawned))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Session not found"})
    end
  end

  defp resolve_session(id_or_uuid), do: Sessions.resolve(id_or_uuid)

  @doc """
  POST /api/v1/sessions/:uuid/end - End a session with optional summary and final status.
  """
  def end_session(conn, %{"uuid" => uuid} = params) do
    case Sessions.get_session_by_uuid(uuid) do
      {:ok, session} ->
        status = params["final_status"] || "waiting"

        attrs =
          if status in ["completed", "failed"] do
            %{
              status: status,
              ended_at: DateTime.utc_now()
            }
          else
            %{status: status}
          end

        case Sessions.update_session(session, attrs) do
          {:ok, updated} ->
            EyeInTheSky.Events.agent_stopped(updated)
            EyeInTheSky.Events.session_updated(updated)

            # Sync team member status on session end
            handle_terminal_status(updated, status)

            json(conn, %{success: true, message: "Session ended", status: updated.status})

          {:error, cs} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed", details: translate_errors(cs)})
        end

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Session not found"})
    end
  end

  @doc """
  GET /api/v1/sessions/:uuid/context - Load session context.
  """
  def get_context(conn, %{"uuid" => uuid}) do
    case Sessions.get_session_by_uuid(uuid) do
      {:ok, session} ->
        case Contexts.get_session_context(session.id) do
          nil ->
            conn |> put_status(:not_found) |> json(%{error: "No context found"})

          ctx ->
            json(conn, %{
              success: true,
              context: ctx.context,
              updated_at: to_string(ctx.updated_at)
            })
        end

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Session not found"})
    end
  end

  @doc """
  PATCH /api/v1/sessions/:uuid/context - Save/update session context.
  """
  def update_context(conn, %{"uuid" => uuid} = params) do
    context = params["context"]

    if is_nil(context) or context == "" do
      conn |> put_status(:bad_request) |> json(%{error: "context is required"})
    else
      case Sessions.get_session_by_uuid(uuid) do
        {:ok, session} -> do_upsert_context(conn, session, context)
        {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "Session not found"})
      end
    end
  end

  defp do_upsert_context(conn, session, context) do
    attrs = %{agent_id: session.agent_id, session_id: session.id, context: context}

    case Contexts.upsert_session_context(attrs) do
      {:ok, sc} ->
        json(conn, %{success: true, context: sc.context})

      {:error, cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed", details: translate_errors(cs)})
    end
  end

  defp trigger_status_side_effects(updated, status) do
    if status do
      if status in ["completed", "failed", "waiting", "stopped"] do
        EyeInTheSky.Events.agent_stopped(updated)
      else
        EyeInTheSky.Events.agent_working(updated)
      end
    end

    EyeInTheSky.Events.session_updated(updated)

    if status in ["completed", "failed"] do
      handle_terminal_status(updated, status)
    end
  end

  defp handle_terminal_status(session, status) do
    member_status = if status == "failed", do: "failed", else: "done"
    EyeInTheSky.Teams.mark_member_done_by_session(session.id, member_status)
  end
end
