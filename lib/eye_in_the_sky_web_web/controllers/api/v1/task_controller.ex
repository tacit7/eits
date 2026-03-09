defmodule EyeInTheSkyWebWeb.Api.V1.TaskController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.{Agents, Notes, Projects, Sessions, Tasks}

  @doc """
  GET /api/v1/tasks - List tasks.
  Query params: project_id, agent_id, session_id, q (search), limit
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 50)

    tasks =
      cond do
        params["q"] && params["q"] != "" ->
          Tasks.search_tasks(params["q"]) |> Enum.take(limit)

        params["session_id"] ->
          session_int_id = resolve_session_int_id(params["session_id"])
          if session_int_id, do: Tasks.list_tasks_for_session(session_int_id) |> Enum.take(limit), else: []

        params["agent_id"] ->
          agent_int_id = resolve_agent_int_id(params["agent_id"])
          if agent_int_id, do: Tasks.list_tasks_for_agent(agent_int_id) |> Enum.take(limit), else: []

        params["project_id"] ->
          Projects.get_project_tasks(parse_int(params["project_id"], nil)) |> Enum.take(limit)

        true ->
          Tasks.list_tasks() |> Enum.take(limit)
      end

    tasks =
      if state_id = parse_int(params["state_id"], nil) do
        Enum.filter(tasks, &(&1.state_id == state_id))
      else
        tasks
      end

    json(conn, %{
      success: true,
      message: "#{length(tasks)} task(s)",
      tasks: Enum.map(tasks, &format_task/1)
    })
  end

  @doc """
  POST /api/v1/tasks - Create a task.
  """
  def create(conn, params) do
    attrs = %{
      uuid: Ecto.UUID.generate(),
      title: params["title"],
      description: params["description"],
      priority: params["priority"],
      state_id: params["state_id"] || 1,
      project_id: params["project_id"],
      agent_id: resolve_agent_int_id(params["agent_id"]),
      due_at: params["due_at"],
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Tasks.create_task(attrs) do
      {:ok, task} ->
        maybe_add_tags(task, params["tags"])
        maybe_link_session(task.id, params["session_id"])

        conn
        |> put_status(:created)
        |> json(%{success: true, message: "Task created", task_id: to_string(task.id)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create task", details: translate_errors(changeset)})
    end
  end

  @doc """
  GET /api/v1/tasks/:id - Show a task.
  """
  def show(conn, %{"id" => id}) do
    try do
      task = Tasks.get_task!(id)
      annotations = Notes.list_notes_for_task(id)
      json(conn, %{success: true, task: format_task(task), annotations: Enum.map(annotations, &format_note/1)})
    rescue
      Ecto.NoResultsError ->
        conn |> put_status(:not_found) |> json(%{error: "Task not found"})
    end
  end

  @doc """
  PATCH /api/v1/tasks/:id - Update a task.
  Body: state_id, priority, state (shorthand: "done", "start")
  """
  def update(conn, %{"id" => id} = params) do
    try do
      task = Tasks.get_task!(id)

      result =
        case params["state"] do
          "done" -> move_to_state(task, "Done")
          "start" -> move_to_state(task, "In Progress")
          _ -> update_attrs(task, params)
        end

      case result do
        {:ok, updated} ->
          json(conn, %{success: true, message: "Task updated", task: format_task(updated)})

        {:error, cs} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed", details: translate_errors(cs)})
      end
    rescue
      Ecto.NoResultsError ->
        conn |> put_status(:not_found) |> json(%{error: "Task not found"})
    end
  end

  @doc """
  DELETE /api/v1/tasks/:id - Delete a task.
  """
  def delete(conn, %{"id" => id}) do
    try do
      task = Tasks.get_task!(id)

      case Tasks.delete_task(task) do
        {:ok, _} ->
          json(conn, %{success: true, message: "Task deleted"})

        {:error, cs} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed", details: translate_errors(cs)})
      end
    rescue
      Ecto.NoResultsError ->
        conn |> put_status(:not_found) |> json(%{error: "Task not found"})
    end
  end

  @doc """
  POST /api/v1/tasks/:id/annotate - Add an annotation note to a task.
  Body: body, title (optional)
  """
  def annotate(conn, %{"id" => task_id} = params) do
    case Notes.create_note(%{
           parent_id: task_id,
           parent_type: "task",
           body: params["body"] || "",
           title: params["title"]
         }) do
      {:ok, note} ->
        conn
        |> put_status(:created)
        |> json(%{success: true, message: "Annotation added", note_id: note.id})

      {:error, cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed", details: translate_errors(cs)})
    end
  end

  @doc """
  POST /api/v1/tasks/:id/sessions - Link a session to a task.
  """
  def link_session(conn, %{"id" => task_id} = params) do
    case params["session_id"] do
      nil ->
        conn |> put_status(:bad_request) |> json(%{error: "session_id is required"})

      session_id ->
        maybe_link_session(task_id, session_id)
        json(conn, %{success: true, message: "Session linked to task #{task_id}"})
    end
  end

  @doc """
  DELETE /api/v1/tasks/:id/sessions/:uuid - Unlink a session from a task.
  """
  def unlink_session(conn, %{"id" => task_id, "uuid" => session_uuid}) do
    int_id =
      case Integer.parse(session_uuid) do
        {n, ""} -> n
        _ ->
          case Sessions.get_session_by_uuid(session_uuid) do
            {:ok, s} -> s.id
            _ -> nil
          end
      end

    task_int_id = if is_binary(task_id), do: String.to_integer(task_id), else: task_id

    if int_id do
      import Ecto.Query, only: [from: 2]
      EyeInTheSkyWeb.Repo.delete_all(
        from(ts in "task_sessions", where: ts.task_id == ^task_int_id and ts.session_id == ^int_id)
      )
      json(conn, %{success: true, message: "Session unlinked from task #{task_id}"})
    else
      conn |> put_status(:not_found) |> json(%{error: "Session not found"})
    end
  end

  # Helpers

  defp format_task(task) do
    %{
      id: task.id,
      title: task.title,
      description: task.description,
      priority: task.priority,
      state: if(Ecto.assoc_loaded?(task.state) && task.state, do: task.state.name),
      state_id: task.state_id,
      due_at: task.due_at
    }
  end

  defp format_note(note) do
    %{id: note.id, title: note.title, body: note.body, starred: note.starred || 0}
  end

  defp move_to_state(task, state_name) do
    state = Tasks.get_workflow_state_by_name(state_name)

    if state do
      Tasks.update_task_state(task, state.id)
    else
      {:error, "Workflow state '#{state_name}' not found"}
    end
  end

  defp update_attrs(task, params) do
    attrs =
      %{}
      |> maybe_put(:state_id, params["state_id"])
      |> maybe_put(:priority, params["priority"])
      |> maybe_put(:description, params["description"])
      |> maybe_put(:due_at, params["due_at"])

    Tasks.update_task(task, attrs)
  end

  defp maybe_link_session(_task_id, nil), do: :ok

  defp maybe_link_session(task_id, session_id) when is_binary(session_id) do
    int_id =
      case Integer.parse(session_id) do
        {n, ""} ->
          n

        _ ->
          case Sessions.get_session_by_uuid(session_id) do
            {:ok, s} -> s.id
            _ -> nil
          end
      end

    task_int_id = if is_binary(task_id), do: String.to_integer(task_id), else: task_id

    if int_id do
      EyeInTheSkyWeb.Repo.insert_all("task_sessions", [%{task_id: task_int_id, session_id: int_id}],
        on_conflict: :nothing
      )
    end

    :ok
  end

  defp resolve_agent_int_id(nil), do: nil

  defp resolve_agent_int_id(uuid) do
    case Agents.get_agent_by_uuid(uuid) do
      {:ok, agent} -> agent.id
      _ -> nil
    end
  end

  defp resolve_session_int_id(nil), do: nil

  defp resolve_session_int_id(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ ->
        case Sessions.get_session_by_uuid(val) do
          {:ok, s} -> s.id
          _ -> nil
        end
    end
  end

  defp maybe_add_tags(_task, nil), do: :ok
  defp maybe_add_tags(_task, []), do: :ok

  defp maybe_add_tags(_task, tags) do
    Enum.each(tags, fn tag_name -> Tasks.get_or_create_tag(tag_name) end)
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
