defmodule EyeInTheSkyWebWeb.Api.V1.SessionController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.{Agents, Contexts, Sessions, Projects}

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
      # Resolve project_id from project_name if needed
      project_id = resolve_project_id(params)

      # Build Agent (agents table) attrs
      agent_attrs = %{
        uuid: params["agent_id"] || session_uuid,
        description: params["agent_description"] || params["description"],
        project_id: project_id,
        project_name: params["project_name"],
        git_worktree_path: params["worktree_path"],
        source: "hook"
      }

      case Agents.create_agent(agent_attrs) do
        {:ok, agent} ->
          # Parse model info
          {model_provider, model_name} = parse_model(params["model"])

          # Build Session (sessions table) attrs
          session_attrs = %{
            uuid: session_uuid,
            agent_id: agent.id,
            name: params["name"] || params["description"],
            status: "working",
            started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
            provider: params["provider"] || "claude",
            model: params["model"],
            model_provider: model_provider,
            model_name: model_name,
            project_id: project_id,
            git_worktree_path: params["worktree_path"]
          }

          create_fn =
            if model_name,
              do: &Sessions.create_session_with_model/1,
              else: &Sessions.create_session/1

          case create_fn.(session_attrs) do
            {:ok, session} ->
              Phoenix.PubSub.broadcast(
                EyeInTheSkyWeb.PubSub,
                "agents",
                {:agent_updated, session}
              )

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

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to create agent", details: translate_errors(changeset)})
      end
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
          |> maybe_put(:status, status)
          |> maybe_put(:intent, params["intent"])
          |> maybe_put(:last_activity_at, DateTime.utc_now() |> DateTime.to_iso8601())

        # For terminal states, set ended_at
        attrs =
          if status in ["completed", "failed"] do
            Map.put(
              attrs,
              :ended_at,
              params["ended_at"] || DateTime.utc_now() |> DateTime.to_iso8601()
            )
          else
            attrs
          end

        case Sessions.update_session(session, attrs) do
          {:ok, updated} ->
            # Broadcast status change
            topic =
              if status in ["completed", "failed"] do
                {:agent_stopped, updated}
              else
                {:agent_working, updated}
              end

            Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agent:working", topic)
            Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agents", {:agent_updated, updated})

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
  GET /api/v1/sessions - Search sessions.
  Query params: q, limit (default 20)
  """
  def index(conn, params) do
    query = params["q"] || ""
    limit = parse_int(params["limit"], 20)

    opts = [search_query: query]
    opts = if params["project_id"], do: Keyword.put(opts, :project_id, parse_int(params["project_id"], nil)), else: opts
    opts = if params["status"], do: Keyword.put(opts, :status, params["status"]), else: opts

    results = Sessions.list_sessions_filtered(opts) |> Enum.take(limit)

    json(conn, %{
      success: true,
      message: "Found #{length(results)} session(s)",
      results:
        Enum.map(results, fn s ->
          %{id: s.id, uuid: s.uuid, description: s.description, status: s.status}
        end)
    })
  end

  @doc """
  GET /api/v1/sessions/:uuid - Get session info.
  """
  def show(conn, %{"uuid" => uuid}) do
    case Sessions.get_session_by_uuid(uuid) do
      {:ok, session} ->
        agent_uuid = resolve_agent_uuid(session.agent_id)

        json(conn, %{
          agent_id: agent_uuid,
          session_id: uuid,
          project_id: session.project_id,
          status: session.status,
          initialized: true
        })

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Session not found"})
    end
  end

  @doc """
  POST /api/v1/sessions/:uuid/end - End a session with optional summary and final status.
  """
  def end_session(conn, %{"uuid" => uuid} = params) do
    case Sessions.get_session_by_uuid(uuid) do
      {:ok, session} ->
        status = params["final_status"] || "completed"

        attrs = %{
          status: status,
          ended_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case Sessions.update_session(session, attrs) do
          {:ok, updated} ->
            Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agent:working", {:agent_stopped, updated})
            Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agents", {:agent_updated, updated})
            json(conn, %{success: true, message: "Session ended", status: updated.status})

          {:error, cs} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "Failed", details: translate_errors(cs)})
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
        {:ok, session} ->
          attrs = %{agent_id: session.agent_id, session_id: session.id, context: context}

          case Contexts.upsert_session_context(attrs) do
            {:ok, sc} ->
              json(conn, %{success: true, context: sc.context})

            {:error, cs} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: "Failed", details: translate_errors(cs)})
          end

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "Session not found"})
      end
    end
  end

  # Resolve project_id from project_name or direct project_id param
  defp resolve_project_id(params) do
    cond do
      params["project_id"] ->
        params["project_id"]

      params["project_name"] ->
        case Projects.get_project_by_name(params["project_name"]) do
          %{id: id} -> id
          nil -> nil
        end

      true ->
        nil
    end
  end

  # Parse model string like "claude-sonnet-4-5-20250929" into provider/name
  defp parse_model(nil), do: {"claude", nil}
  defp parse_model(""), do: {"claude", nil}

  defp parse_model(model) when is_binary(model) do
    cond do
      String.starts_with?(model, "claude-") ->
        {"anthropic", model}

      String.contains?(model, "/") ->
        [provider | rest] = String.split(model, "/", parts: 2)
        {provider, Enum.join(rest, "/")}

      true ->
        {"anthropic", model}
    end
  end

  defp resolve_agent_uuid(nil), do: nil

  defp resolve_agent_uuid(agent_int_id) do
    case EyeInTheSkyWeb.Agents.get_agent(agent_int_id) do
      {:ok, agent} -> agent.uuid
      _ -> nil
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp translate_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp translate_errors(_), do: %{}
end
