defmodule EyeInTheSkyWebWeb.Api.V1.SessionContextController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.{Contexts, Sessions}

  @doc """
  GET /api/v1/session-context/:uuid - Load session context by session UUID.
  """
  def show(conn, %{"uuid" => uuid}) do
    case Sessions.get_session_by_uuid(uuid) do
      {:ok, session} ->
        case Contexts.get_session_context(session.id) do
          nil ->
            conn |> put_status(:not_found) |> json(%{error: "No context found for session"})

          ctx ->
            json(conn, %{
              success: true,
              context: ctx.context,
              created_at: to_string(ctx.created_at),
              updated_at: to_string(ctx.updated_at)
            })
        end

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Session not found"})
    end
  end

  @doc """
  POST /api/v1/session-context - Save session context (markdown).

  Accepts agent_id (UUID), session_id (optional UUID), context (markdown string).
  Looks up agent by UUID to get integer IDs for the session_context table.
  """
  def create(conn, params) do
    agent_uuid = params["agent_id"]
    context = params["context"]

    cond do
      is_nil(agent_uuid) or agent_uuid == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "agent_id is required"})

      is_nil(context) or context == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "context is required"})

      true ->
        case Sessions.get_session_by_uuid(agent_uuid) do
          {:ok, agent} ->
            attrs = %{
              agent_id: agent.agent_id,
              session_id: agent.id,
              context: context
            }

            case Contexts.upsert_session_context(attrs) do
              {:ok, sc} ->
                conn
                |> put_status(:created)
                |> json(%{
                  id: sc.id,
                  agent_id: sc.agent_id,
                  session_id: sc.session_id,
                  context: sc.context
                })

              {:error, %Ecto.Changeset{} = changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Failed to save context", details: translate_errors(changeset)})
            end

          {:error, :not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "Agent not found"})
        end
    end
  end

  defp translate_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
