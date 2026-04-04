defmodule EyeInTheSkyWeb.Api.V1.TaskController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, Notes, Projects, Sessions, Tasks}
  alias EyeInTheSky.Tasks.WorkflowState
  alias EyeInTheSky.Utils.ToolHelpers, as: Helpers
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

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
          session_int_id =
            case Helpers.resolve_session_int_id(params["session_id"]) do
              {:ok, id} -> id
              _ -> nil
            end

          if session_int_id,
            do: Tasks.list_tasks_for_session(session_int_id) |> Enum.take(limit),
            else: []

        params["agent_id"] ->
          agent_int_id = resolve_agent_int_id(params["agent_id"])

          if agent_int_id,
            do: Tasks.list_tasks_for_agent(agent_int_id) |> Enum.take(limit),
            else: []

        params["project_id"] ->
          Projects.get_project_tasks(parse_int(params["project_id"], nil)) |> Enum.take(limit)

        true ->
          Tasks.list_tasks() |> Enum.take(limit)
      end

    tasks =
      if state_id = parse_int(params["state_id"], nil) do
        tasks |> Enum.filter(&(&1.state_id == state_id)) |> Enum.take(limit)
      else
        tasks
      end

    json(conn, %{
      success: true,
      message: "#{length(tasks)} task(s)",
      tasks: Enum.map(tasks, &ApiPresenter.present_task/1)
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
      state_id: params["state_id"] || WorkflowState.todo_id(),
      project_id: params["project_id"],
      team_id: parse_int(params["team_id"], nil),
      agent_id: resolve_agent_int_id(params["agent_id"]),
      due_at: params["due_at"],
      created_at: DateTime.utc_now()
    }

    case Tasks.create_task(attrs) do
      {:ok, task} ->
        maybe_add_tags(task, params["tags"])
        maybe_add_tag_ids(task, params["tag_ids"])
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
    case Tasks.get_task(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Task not found"})

      task ->
        annotations = Notes.list_notes_for_task(id)
        presented = ApiPresenter.present_task(task)

        json(conn, %{
          success: true,
          task: presented,
          # Top-level convenience fields so scripts can read .project_id / .title
          # without reaching into .task (backwards-compat with callers that assumed flat response)
          id: presented.id,
          title: presented.title,
          project_id: task.project_id,
          state_id: presented.state_id,
          annotations: Enum.map(annotations, &ApiPresenter.present_note/1)
        })
    end
  end

  @doc """
  PATCH /api/v1/tasks/:id - Update a task.
  Body: state_id, priority, state (shorthand: "done", "start")
  """
  def update(conn, %{"id" => id} = params) do
    case Tasks.get_task(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Task not found"})

      task ->
        result =
          case params["state"] do
            "done" -> move_to_state(task, "Done")
            "start" -> move_to_state(task, "In Progress")
            _ -> update_attrs(task, params)
          end

        case result do
          {:ok, updated} ->
            if params["state"] == "start" do
              maybe_link_session(updated.id, params["session_id"])
            end

            json(conn, %{
              success: true,
              message: "Task updated",
              task: ApiPresenter.present_task(updated)
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to update task", details: translate_errors(changeset)})
        end
    end
  end

  @doc """
  DELETE /api/v1/tasks/:id - Delete a task.
  """
  def delete(conn, %{"id" => id}) do
    case Tasks.get_task(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Task not found"})

      task ->
        case Tasks.delete_task(task) do
          {:ok, _} ->
            json(conn, %{success: true, message: "Task deleted"})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete task", details: translate_errors(changeset)})
        end
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
    int_id = resolve_session_int_id(session_uuid)
    task_int_id = parse_task_id(task_id)

    if int_id do
      Tasks.unlink_session_from_task(task_int_id, int_id)
      json(conn, %{success: true, message: "Session unlinked from task #{task_id}"})
    else
      conn |> put_status(:not_found) |> json(%{error: "Session not found"})
    end
  end

  # Helpers

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
      |> Helpers.maybe_put(:state_id, params["state_id"])
      |> Helpers.maybe_put(:priority, params["priority"])
      |> Helpers.maybe_put(:description, params["description"])
      |> Helpers.maybe_put(:due_at, params["due_at"])

    Tasks.update_task(task, attrs)
  end

  defp maybe_link_session(_task_id, nil), do: :ok

  defp maybe_link_session(task_id, session_id) when is_binary(session_id) do
    int_id = resolve_session_int_id(session_id)
    task_int_id = parse_task_id(task_id)

    if int_id do
      Tasks.link_session_to_task(task_int_id, int_id)
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

  defp maybe_add_tags(_task, nil), do: :ok
  defp maybe_add_tags(_task, []), do: :ok

  defp maybe_add_tags(task, tags) when is_list(tags) do
    Tasks.replace_task_tags(task.id, tags)
  end

  defp maybe_add_tag_ids(_task, nil), do: :ok
  defp maybe_add_tag_ids(_task, []), do: :ok

  defp maybe_add_tag_ids(task, tag_ids) when is_list(tag_ids) do
    Enum.each(tag_ids, fn tag_id ->
      case tag_id do
        id when is_integer(id) -> Tasks.link_tag_to_task(task.id, id)
        id when is_binary(id) -> Tasks.link_tag_to_task(task.id, String.to_integer(id))
        _ -> :ok
      end
    end)
  end

  defp resolve_session_int_id(raw) do
    resolve_id(raw, &Sessions.get_session_by_uuid/1)
  end

  defp parse_task_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> id
    end
  end

  defp parse_task_id(id), do: id
end
