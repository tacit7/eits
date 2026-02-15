defmodule EyeInTheSkyWebWeb.Api.V1.SessionController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.{Agents, ChatAgents, Projects}

  @doc """
  POST /api/v1/sessions - Register a new session (SessionStart hook).

  Creates a ChatAgent (chat identity) and an Agent (execution session).
  Mirrors the i-start-session MCP tool flow.
  """
  def create(conn, params) do
    session_uuid = params["session_id"]

    if is_nil(session_uuid) or session_uuid == "" do
      conn |> put_status(:bad_request) |> json(%{error: "session_id is required"})
    else
      # Resolve project_id from project_name if needed
      project_id = resolve_project_id(params)

      # Build ChatAgent (agents table) attrs
      chat_agent_attrs = %{
        uuid: params["agent_id"] || session_uuid,
        description: params["agent_description"] || params["description"],
        project_id: project_id,
        project_name: params["project_name"],
        git_worktree_path: params["worktree_path"],
        source: "hook"
      }

      case ChatAgents.create_chat_agent(chat_agent_attrs) do
        {:ok, chat_agent} ->
          # Parse model info
          {model_provider, model_name} = parse_model(params["model"])

          # Build Agent (sessions table) attrs
          agent_attrs = %{
            uuid: session_uuid,
            agent_id: chat_agent.id,
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
              do: &Agents.create_execution_agent_with_model/1,
              else: &Agents.create_execution_agent/1

          case create_fn.(agent_attrs) do
            {:ok, agent} ->
              Phoenix.PubSub.broadcast(
                EyeInTheSkyWeb.PubSub,
                "agents",
                {:agent_updated, agent}
              )

              conn
              |> put_status(:created)
              |> json(%{
                id: agent.id,
                uuid: agent.uuid,
                agent_id: chat_agent.id,
                chat_agent_uuid: chat_agent.uuid,
                status: agent.status
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
    case Agents.get_execution_agent_by_uuid(uuid) do
      {:ok, agent} ->
        status = params["status"]

        attrs =
          %{}
          |> maybe_put(:status, status)
          |> maybe_put(:last_activity_at, DateTime.utc_now() |> DateTime.to_iso8601())

        # For terminal states, set ended_at
        attrs =
          if status in ["completed", "failed"] do
            Map.put(attrs, :ended_at, params["ended_at"] || DateTime.utc_now() |> DateTime.to_iso8601())
          else
            attrs
          end

        case Agents.update_execution_agent(agent, attrs) do
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
      String.starts_with?(model, "claude-") -> {"anthropic", model}
      String.contains?(model, "/") ->
        [provider | rest] = String.split(model, "/", parts: 2)
        {provider, Enum.join(rest, "/")}
      true -> {"anthropic", model}
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
