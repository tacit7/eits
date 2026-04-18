defmodule EyeInTheSkyWeb.Api.V1.TaskController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, Notes, Tasks}
  alias EyeInTheSky.Tasks.WorkflowState
  alias EyeInTheSky.Utils.ToolHelpers, as: Helpers
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  GET /api/v1/tasks - List tasks.
  Query params: project_id, agent_id, session_id, q (search), limit
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 50)
    tasks = fetch_tasks(params, limit)

    json(conn, %{
      success: true,
      message: "#{length(tasks)} task(s)",
      tasks: Enum.map(tasks, &ApiPresenter.present_task/1)
    })
  end

  defp fetch_tasks(params, limit) do
    tasks = fetch_tasks_by_filter(params, limit)

    if state_id = parse_int(params["state_id"], nil) do
      tasks |> Enum.filter(&(&1.state_id == state_id)) |> Enum.take(limit)
    else
      tasks
    end
  end

  defp fetch_tasks_by_filter(%{"q" => q}, limit) when is_binary(q) and q != "" do
    Tasks.search_tasks(q) |> Enum.take(limit)
  end

  defp fetch_tasks_by_filter(%{"session_id" => session_id}, limit) do
    session_int_id =
      case Helpers.resolve_session_int_id(session_id) do
        {:ok, id} -> id
        _ -> nil
      end

    if session_int_id,
      do: Tasks.list_tasks_for_session(session_int_id) |> Enum.take(limit),
      else: []
  end

  defp fetch_tasks_by_filter(%{"agent_id" => agent_id}, limit) do
    agent_int_id = resolve_agent_int_id(agent_id)

    if agent_int_id,
      do: Tasks.list_tasks_for_agent(agent_int_id) |> Enum.take(limit),
      else: []
  end

  defp fetch_tasks_by_filter(%{"project_id" => project_id}, limit) do
    case parse_int(project_id, nil) do
      nil -> []
      project_int_id -> Tasks.list_tasks_for_project(project_int_id) |> Enum.take(limit)
    end
  end

  defp fetch_tasks_by_filter(_params, limit) do
    Tasks.list_tasks() |> Enum.take(limit)
  end

  @doc """
  POST /api/v1/tasks - Create a task.
  """
  def create(conn, params) do
    attrs = %{
      uuid: Ecto.UUID.generate(),
      title: trim_param(params["title"]),
      description: trim_param(params["description"]),
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
        Tasks.associate_task(task, params)

        conn
        |> put_status(:created)
        |> json(%{success: true, message: "Task created", task_id: to_string(task.id)})

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  GET /api/v1/tasks/:id - Show a task.
  """
  def show(conn, %{"id" => id}) do
    case Tasks.get_task(id) do
      {:error, :not_found} ->
        {:error, :not_found, "Task not found"}

      {:ok, task} ->
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
      {:error, :not_found} -> {:error, :not_found, "Task not found"}
      {:ok, task} -> do_update_task(conn, task, params)
    end
  end

  defp do_update_task(conn, task, params) do
    result =
      case WorkflowState.resolve_alias(params["state"]) do
        {:ok, state_name} ->
          move_to_state(task, state_name)

        {:error, :no_alias} ->
          update_attrs(task, params)

        {:error, :invalid_alias} ->
          {:error,
           {:bad_alias,
            "Unknown state alias '#{params["state"]}'. Valid aliases: done, start, in-review, review, todo"}}
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

      {:error, {:bad_alias, message}} ->
        {:error, message}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  DELETE /api/v1/tasks/:id - Delete a task.
  """
  def delete(conn, %{"id" => id}) do
    case Tasks.get_task(id) do
      {:error, :not_found} ->
        {:error, :not_found, "Task not found"}

      {:ok, task} ->
        case Tasks.delete_task(task) do
          {:ok, _} ->
            json(conn, %{success: true, message: "Task deleted"})

          {:error, changeset} ->
            {:error, changeset}
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
           body: trim_param(params["body"] || ""),
           title: trim_param(params["title"])
         }) do
      {:ok, note} ->
        conn
        |> put_status(:created)
        |> json(%{success: true, message: "Annotation added", note_id: note.id})

      {:error, cs} ->
        {:error, cs}
    end
  end

  @doc """
  POST /api/v1/tasks/:id/complete - Atomically annotate and move task to Done.
  Body: message (required)
  """
  def complete(conn, %{"id" => id} = params) do
    message = trim_param(params["message"] || "")

    with false <- message == "",
         {:ok, task} <- Tasks.get_task(id),
         {:ok, %{task: updated}} <- Tasks.complete_task(task, message) do
      json(conn, %{
        success: true,
        message: "Task completed",
        task: ApiPresenter.present_task(updated)
      })
    else
      true ->
        {:error, "message is required"}

      {:error, :not_found} ->
        {:error, :not_found, "Task not found"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, _reason} ->
        {:error, "Failed to complete task"}
    end
  end

  @doc """
  POST /api/v1/tasks/:id/sessions - Link a session to a task.
  """
  def link_session(conn, %{"id" => task_id} = params) do
    case params["session_id"] do
      nil ->
        {:error, :bad_request, "session_id is required"}

      session_id ->
        case Tasks.get_task(task_id) do
          {:ok, _task} ->
            maybe_link_session(task_id, session_id)
            json(conn, %{success: true, message: "Session linked to task #{task_id}"})

          {:error, :not_found} ->
            {:error, :bad_request, "Invalid task ID"}
        end
    end
  end

  @doc """
  DELETE /api/v1/tasks/:id/sessions/:uuid - Unlink a session from a task.
  """
  def unlink_session(conn, %{"id" => task_id, "uuid" => session_uuid}) do
    case Tasks.get_task(task_id) do
      {:error, :not_found} ->
        {:error, :bad_request, "Invalid task ID"}

      {:ok, task} ->
        int_id =
          case Helpers.resolve_session_int_id(session_uuid) do
            {:ok, id} -> id
            _ -> nil
          end

        if int_id do
          Tasks.unlink_session_from_task(task.id, int_id)
          json(conn, %{success: true, message: "Session unlinked from task #{task_id}"})
        else
          {:error, :not_found, "Session not found"}
        end
    end
  end

  # Helpers

  defp move_to_state(task, state_name) do
    case Tasks.get_workflow_state_by_name(state_name) do
      {:ok, state} -> Tasks.update_task_state(task, state.id)
      {:error, :not_found} -> {:error, "Workflow state '#{state_name}' not found"}
    end
  end

  defp update_attrs(task, params) do
    attrs =
      %{}
      |> Helpers.maybe_put(:state_id, params["state_id"])
      |> Helpers.maybe_put(:priority, params["priority"])
      |> Helpers.maybe_put(:description, trim_param(params["description"]))
      |> Helpers.maybe_put(:due_at, params["due_at"])

    Tasks.update_task(task, attrs)
  end

  defp maybe_link_session(_task_id, nil), do: :ok

  defp maybe_link_session(task_id, session_id) when is_binary(session_id) do
    int_id =
      case Helpers.resolve_session_int_id(session_id) do
        {:ok, id} -> id
        _ -> nil
      end

    case parse_task_id(task_id) do
      nil ->
        :ok

      task_int_id ->
        if int_id do
          Tasks.link_session_to_task(task_int_id, int_id)
        end

        :ok
    end
  end

  defp resolve_agent_int_id(uuid), do: resolve_id(uuid, &Agents.get_agent_by_uuid/1)

  defp parse_task_id(id) when is_binary(id), do: Helpers.parse_int(id) || id
  defp parse_task_id(id), do: id
end
