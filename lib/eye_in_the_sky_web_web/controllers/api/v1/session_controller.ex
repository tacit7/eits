defmodule EyeInTheSkyWebWeb.Api.V1.SessionController do
  use EyeInTheSkyWebWeb, :controller

  action_fallback EyeInTheSkyWebWeb.Api.V1.FallbackController

  import EyeInTheSkyWebWeb.ControllerHelpers

  alias EyeInTheSkyWeb.{Agents, Contexts, Sessions, Projects}
  alias EyeInTheSkyWeb.MCP.Tools.Helpers

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

      # Check if session already exists (resumed session)
      case Sessions.get_session_by_uuid(session_uuid) do
        {:ok, existing} ->
          case Sessions.update_session(existing, %{
                 status: "working",
                 last_activity_at: DateTime.utc_now() |> DateTime.to_iso8601()
               }) do
            {:ok, updated} ->
              Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agents", {:agent_updated, updated})

              json(conn, %{
                id: updated.id,
                uuid: updated.uuid,
                agent_id: nil,
                agent_uuid: nil,
                status: updated.status
              })

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to update session", details: translate_errors(changeset)})
          end

        {:error, :not_found} ->
          with {:ok, agent} <- find_or_create_agent(agent_attrs) do
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
          else
            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to create agent", details: translate_errors(changeset)})
          end
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

            # Sync team member status when session completes/fails
            if status in ["completed", "failed"] do
              member_status = if status == "failed", do: "failed", else: "done"
              EyeInTheSkyWeb.Teams.mark_member_done_by_session(updated.id, member_status)
            end

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
            last_activity_at: DateTime.utc_now() |> DateTime.to_iso8601()
          })

          tool_input = params["tool_input"] || %{}

          case type do
            "pre" ->
              input_json = Jason.encode!(tool_input)
              body = "Tool: #{tool_name}\n#{input_json}" |> String.slice(0..3999)

              EyeInTheSkyWeb.Messages.create_message(%{
                uuid: Ecto.UUID.generate(),
                session_id: session.id,
                sender_role: "tool",
                recipient_role: "user",
                direction: "inbound",
                body: body,
                status: "delivered",
                provider: "claude",
                metadata: %{"stream_type" => "tool_use", "tool_name" => tool_name, "input" => tool_input}
              })

              Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agent:working", {:agent_working, session})
              Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "session:#{session.id}", {:tool_use, tool_name, tool_input})

            "post" ->
              input_json = Jason.encode!(tool_input)
              body = "Tool: #{tool_name} (completed)\n#{input_json}" |> String.slice(0..3999)

              EyeInTheSkyWeb.Messages.create_message(%{
                uuid: Ecto.UUID.generate(),
                session_id: session.id,
                sender_role: "tool",
                recipient_role: "user",
                direction: "inbound",
                body: body,
                status: "delivered",
                provider: "claude",
                metadata: %{"stream_type" => "tool_result", "tool_name" => tool_name}
              })

              Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "session:#{session.id}", {:tool_result, tool_name, false})

            _ ->
              nil
          end

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
        agent_uuid = Helpers.resolve_agent_uuid(session.agent_id)

        json(conn, %{
          id: session.id,
          agent_id: agent_uuid,
          agent_int_id: session.agent_id,
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
            Phoenix.PubSub.broadcast(
              EyeInTheSkyWeb.PubSub,
              "agent:working",
              {:agent_stopped, updated}
            )

            Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agents", {:agent_updated, updated})

            # Sync team member status on session end
            member_status = if status == "failed", do: "failed", else: "done"
            EyeInTheSkyWeb.Teams.mark_member_done_by_session(updated.id, member_status)

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
        {:ok, session} ->
          attrs = %{agent_id: session.agent_id, session_id: session.id, context: context}

          case Contexts.upsert_session_context(attrs) do
            {:ok, sc} ->
              json(conn, %{success: true, context: sc.context})

            {:error, cs} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed", details: translate_errors(cs)})
          end

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "Session not found"})
      end
    end
  end

  defp find_or_create_agent(%{uuid: uuid} = attrs) do
    case Agents.get_agent_by_uuid(uuid) do
      {:ok, existing} ->
        {:ok, existing}

      {:error, :not_found} ->
        case Agents.create_agent(attrs) do
          {:ok, agent} ->
            {:ok, agent}

          {:error, %Ecto.Changeset{}} = err ->
            err

          _ ->
            case Agents.get_agent_by_uuid(uuid) do
              {:ok, existing} -> {:ok, existing}
              err -> err
            end
        end
    end
  rescue
    Ecto.ConstraintError ->
      case Agents.get_agent_by_uuid(uuid) do
        {:ok, existing} -> {:ok, existing}
        _ -> {:error, :constraint_race}
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

end
