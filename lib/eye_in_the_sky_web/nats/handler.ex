defmodule EyeInTheSkyWeb.NATS.Handler do
  @moduledoc """
  Dispatches NATS messages by subject to the appropriate context functions.

  Uses the same business logic as the REST API controllers.

  Subjects:
    events.session.start    - Register new session
    events.session.update   - Update session status (end/stop/compact)
    events.session.context  - Save session context
    events.commits          - Track git commits
    events.notes            - Add notes
    events.tool.use         - PostToolUse for Bash/Write/Edit
    events.todo             - Task management operations
  """

  require Logger

  alias EyeInTheSkyWeb.{Agents, ChatAgents, Commits, Contexts, Notes, Projects, Tasks}

  def handle("events.session.start", payload) do
    session_uuid = payload["session_id"]

    unless is_nil(session_uuid) or session_uuid == "" do
      project_id = resolve_project_id(payload)

      chat_agent_attrs = %{
        uuid: payload["agent_id"] || session_uuid,
        description: payload["agent_description"] || payload["description"],
        project_id: project_id,
        project_name: payload["project_name"],
        git_worktree_path: payload["worktree_path"],
        source: "hook"
      }

      with {:ok, chat_agent} <- ChatAgents.create_chat_agent(chat_agent_attrs) do
        {model_provider, model_name} = parse_model(payload["model"])

        agent_attrs = %{
          uuid: session_uuid,
          agent_id: chat_agent.id,
          name: payload["name"] || payload["description"],
          status: "working",
          started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          provider: payload["provider"] || "claude",
          model: payload["model"],
          model_provider: model_provider,
          model_name: model_name,
          project_id: project_id,
          git_worktree_path: payload["worktree_path"]
        }

        create_fn =
          if model_name,
            do: &Agents.create_execution_agent_with_model/1,
            else: &Agents.create_execution_agent/1

        case create_fn.(agent_attrs) do
          {:ok, agent} ->
            Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agents", {:agent_updated, agent})
            Logger.info("[NATS.Handler] Session started: #{session_uuid}")

          {:error, reason} ->
            Logger.error("[NATS.Handler] Failed to create agent: #{inspect(reason)}")
        end
      else
        {:error, reason} ->
          Logger.error("[NATS.Handler] Failed to create chat agent: #{inspect(reason)}")
      end
    end
  end

  def handle("events.session.update", payload) do
    uuid = payload["session_id"] || payload["uuid"]
    status = payload["status"]

    with {:ok, agent} <- Agents.get_execution_agent_by_uuid(uuid) do
      attrs =
        %{last_activity_at: DateTime.utc_now() |> DateTime.to_iso8601()}
        |> maybe_put(:status, status)

      attrs =
        if status in ["completed", "failed"] do
          Map.put(attrs, :ended_at, payload["ended_at"] || DateTime.utc_now() |> DateTime.to_iso8601())
        else
          attrs
        end

      case Agents.update_execution_agent(agent, attrs) do
        {:ok, updated} ->
          topic = if status in ["completed", "failed"], do: {:agent_stopped, updated}, else: {:agent_working, updated}
          Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agent:working", topic)
          Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agents", {:agent_updated, updated})
          Logger.info("[NATS.Handler] Session updated: #{uuid} -> #{status}")

        {:error, reason} ->
          Logger.error("[NATS.Handler] Failed to update session #{uuid}: #{inspect(reason)}")
      end
    else
      {:error, :not_found} ->
        Logger.warning("[NATS.Handler] Session not found for update: #{uuid}")
    end
  end

  def handle("events.session.context", payload) do
    agent_uuid = payload["agent_id"]
    context = payload["context"]

    with {:ok, agent} <- Agents.get_execution_agent_by_uuid(agent_uuid) do
      attrs = %{agent_id: agent.agent_id, session_id: agent.id, context: context}

      case Contexts.upsert_session_context(attrs) do
        {:ok, _sc} ->
          Logger.info("[NATS.Handler] Context saved for #{agent_uuid}")

        {:error, reason} ->
          Logger.error("[NATS.Handler] Failed to save context: #{inspect(reason)}")
      end
    else
      {:error, :not_found} ->
        Logger.warning("[NATS.Handler] Agent not found for context: #{agent_uuid}")
    end
  end

  def handle("events.commits", payload) do
    agent_uuid = payload["agent_id"]
    hashes = payload["commit_hashes"] || []
    messages = payload["commit_messages"] || []

    with {:ok, agent} <- Agents.get_execution_agent_by_uuid(agent_uuid) do
      Enum.with_index(hashes, fn hash, idx ->
        case Commits.create_commit(%{
               session_id: agent.id,
               commit_hash: hash,
               commit_message: Enum.at(messages, idx)
             }) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.error("[NATS.Handler] Failed to create commit #{hash}: #{inspect(reason)}")
        end
      end)

      Logger.info("[NATS.Handler] #{length(hashes)} commit(s) tracked for #{agent_uuid}")
    else
      {:error, :not_found} ->
        Logger.warning("[NATS.Handler] Agent not found for commits: #{agent_uuid}")
    end
  end

  def handle("events.notes", payload) do
    parent_type = normalize_parent_type(payload["parent_type"])

    attrs = %{
      parent_type: parent_type,
      parent_id: to_string(payload["parent_id"]),
      title: payload["title"],
      body: payload["body"],
      starred: payload["starred"] || 0
    }

    case Notes.create_note(attrs) do
      {:ok, _note} ->
        Logger.info("[NATS.Handler] Note created: #{parent_type}/#{payload["parent_id"]}")

      {:error, reason} ->
        Logger.error("[NATS.Handler] Failed to create note: #{inspect(reason)}")
    end
  end

  def handle("events.tool.use", payload) do
    # PostToolUse hook data - log tool usage for the session
    session_uuid = payload["session_id"]
    tool_name = payload["tool_name"]

    with {:ok, agent} <- Agents.get_execution_agent_by_uuid(session_uuid) do
      # Update last_activity_at to track liveness
      Agents.update_execution_agent(agent, %{
        last_activity_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

      Phoenix.PubSub.broadcast(
        EyeInTheSkyWeb.PubSub,
        "agent:working",
        {:agent_working, agent}
      )

      Logger.debug("[NATS.Handler] Tool use: #{tool_name} in #{session_uuid}")
    else
      {:error, :not_found} ->
        Logger.debug("[NATS.Handler] Session not found for tool.use: #{session_uuid}")
    end
  end

  def handle("events.todo", payload) do
    command = payload["command"]
    task_id = payload["task_id"]

    case command do
      "create" ->
        attrs = %{
          title: payload["title"],
          description: payload["description"],
          priority: payload["priority"],
          tags: payload["tags"]
        }

        case Tasks.create_task(attrs) do
          {:ok, task} ->
            Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "tasks", {:task_created, task})
            Logger.info("[NATS.Handler] Task created: #{task.id}")

          {:error, reason} ->
            Logger.error("[NATS.Handler] Failed to create task: #{inspect(reason)}")
        end

      cmd when cmd in ["start", "done"] ->
        if task_id do
          state_id = if cmd == "start", do: 2, else: 3

          try do
            task = Tasks.get_task!(task_id)

            case Tasks.update_task(task, %{state_id: state_id}) do
              {:ok, updated} ->
                Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "tasks", {:task_updated, updated})
                Logger.info("[NATS.Handler] Task #{task_id} -> #{cmd}")

              {:error, reason} ->
                Logger.error("[NATS.Handler] Failed to update task #{task_id}: #{inspect(reason)}")
            end
          rescue
            Ecto.NoResultsError ->
              Logger.warning("[NATS.Handler] Task not found: #{task_id}")
          end
        end

      _ ->
        Logger.debug("[NATS.Handler] Unhandled todo command: #{command}")
    end
  end

  def handle(subject, _payload) do
    Logger.debug("[NATS.Handler] Unhandled subject: #{subject}")
  end

  # --- Private helpers (shared with REST controllers) ---

  defp resolve_project_id(params) do
    cond do
      params["project_id"] -> params["project_id"]
      params["project_name"] ->
        case Projects.get_project_by_name(params["project_name"]) do
          %{id: id} -> id
          nil -> nil
        end
      true -> nil
    end
  end

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

  defp normalize_parent_type("sessions"), do: "session"
  defp normalize_parent_type("agents"), do: "agent"
  defp normalize_parent_type("tasks"), do: "task"
  defp normalize_parent_type(type), do: type

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
