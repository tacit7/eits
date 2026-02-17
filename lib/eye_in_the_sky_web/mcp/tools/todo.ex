defmodule EyeInTheSkyWeb.MCP.Tools.Todo do
  @moduledoc "Task management. Commands: create, annotate, start, done, status, tag, list, list-agent, list-session, search, delete, add-session, remove-session, add-session-to-tasks, reindex, vacuum, project-sync"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.Sessions

  schema do
    field :command, :string, required: true, description: "Command to execute"
    field :task_id, :string, description: "Task ID"
    field :title, :string, description: "Task title (for create)"
    field :description, :string, description: "Task description"
    field :priority, :integer, description: "Task priority"
    field :state_id, :integer, description: "Workflow state ID"
    field :project_id, :integer, description: "Project ID"
    field :agent_id, :string, description: "Agent ID"
    field :session_id, :string, description: "Session ID"
    field :query, :string, description: "Search query"
    field :tags, {:list, :string}, description: "Tags to add"
    field :body, :string, description: "Note body (for annotate)"
    field :due_at, :string, description: "Due date (ISO 8601)"
    field :limit, :integer, description: "Result limit"
  end

  @impl true
  def execute(%{"command" => "create"} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    attrs = %{
      title: params["title"],
      description: params["description"],
      priority: params["priority"],
      state_id: params["state_id"] || 1,
      project_id: params["project_id"],
      agent_id: resolve_agent_int_id(params["agent_id"]),
      due_at: params["due_at"]
    }

    result =
      case Tasks.create_task(attrs) do
        {:ok, task} ->
          maybe_add_tags(task, params["tags"])
          %{success: true, message: "Task created", task_id: to_string(task.id)}

        {:error, cs} ->
          %{success: false, message: "Failed: #{inspect(cs.errors)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{"command" => "list"} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    tasks =
      if params["project_id"] do
        EyeInTheSkyWeb.Projects.get_project_tasks(%EyeInTheSkyWeb.Projects.Project{
          id: params["project_id"]
        })
      else
        Tasks.list_tasks()
      end

    limit = params["limit"] || 50
    tasks = Enum.take(tasks, limit)

    result = %{
      success: true,
      message: "#{length(tasks)} task(s)",
      tasks: Enum.map(tasks, &format_task/1)
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{"command" => "list-agent"} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    agent_id = resolve_agent_int_id(params["agent_id"])
    tasks = if agent_id, do: Tasks.list_tasks_for_agent(agent_id), else: []

    result = %{
      success: true,
      message: "#{length(tasks)} task(s) for agent",
      tasks: Enum.map(tasks, &format_task/1)
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{"command" => "list-session"} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    tasks = Tasks.list_tasks_for_session(params["session_id"])

    result = %{
      success: true,
      message: "#{length(tasks)} task(s) for session",
      tasks: Enum.map(tasks, &format_task/1)
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{"command" => "search"} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    query = params["query"] || ""
    tasks = Tasks.search_tasks(query)
    limit = params["limit"] || 50
    tasks = Enum.take(tasks, limit)

    result = %{
      success: true,
      message: "Found #{length(tasks)} task(s)",
      tasks: Enum.map(tasks, &format_task/1)
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{"command" => "done", "task_id" => task_id}, frame) do
    update_task_state(task_id, "Done", frame)
  end

  def execute(%{"command" => "start", "task_id" => task_id}, frame) do
    update_task_state(task_id, "In Progress", frame)
  end

  def execute(%{"command" => "status", "task_id" => task_id} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    result =
      try do
        task = Tasks.get_task!(task_id)

        update_attrs =
          %{}
          |> then(fn m ->
            if params["state_id"], do: Map.put(m, :state_id, params["state_id"]), else: m
          end)
          |> then(fn m ->
            if params["priority"], do: Map.put(m, :priority, params["priority"]), else: m
          end)

        case Tasks.update_task(task, update_attrs) do
          {:ok, _} -> %{success: true, message: "Task updated"}
          {:error, cs} -> %{success: false, message: "Failed: #{inspect(cs.errors)}"}
        end
      rescue
        Ecto.NoResultsError -> %{success: false, message: "Task not found: #{task_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{"command" => "delete", "task_id" => task_id}, frame) do
    alias EyeInTheSkyWeb.Tasks

    result =
      try do
        task = Tasks.get_task!(task_id)

        case Tasks.delete_task(task) do
          {:ok, _} -> %{success: true, message: "Task deleted"}
          {:error, cs} -> %{success: false, message: "Failed: #{inspect(cs.errors)}"}
        end
      rescue
        Ecto.NoResultsError -> %{success: false, message: "Task not found: #{task_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{"command" => "annotate", "task_id" => task_id} = params, frame) do
    alias EyeInTheSkyWeb.Notes

    result =
      case Notes.create_note(%{
             parent_id: task_id,
             parent_type: "tasks",
             body: params["body"] || "",
             title: params["title"]
           }) do
        {:ok, note} -> %{success: true, message: "Annotation added", note_id: note.id}
        {:error, cs} -> %{success: false, message: "Failed: #{inspect(cs.errors)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{"command" => "tag", "task_id" => task_id} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    result =
      try do
        task = Tasks.get_task!(task_id)
        tags = params["tags"] || []
        Enum.each(tags, fn tag_name -> Tasks.get_or_create_tag(tag_name) end)
        %{success: true, message: "Tags updated for task #{task.id}"}
      rescue
        Ecto.NoResultsError -> %{success: false, message: "Task not found: #{task_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{"command" => cmd}, frame) do
    response =
      Response.tool() |> Response.text("Command '#{cmd}' acknowledged (no-op in Phoenix MCP)")

    {:reply, response, frame}
  end

  # Helpers

  defp update_task_state(task_id, state_name, frame) do
    alias EyeInTheSkyWeb.Tasks

    result =
      try do
        task = Tasks.get_task!(task_id)
        state = Tasks.get_workflow_state_by_name(state_name)

        if state do
          case Tasks.update_task_state(task, state.id) do
            {:ok, _} -> %{success: true, message: "Task moved to #{state_name}"}
            {:error, cs} -> %{success: false, message: "Failed: #{inspect(cs.errors)}"}
          end
        else
          %{success: false, message: "Workflow state '#{state_name}' not found"}
        end
      rescue
        Ecto.NoResultsError -> %{success: false, message: "Task not found: #{task_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  defp resolve_agent_int_id(nil), do: nil

  defp resolve_agent_int_id(uuid) do
    case EyeInTheSkyWeb.Sessions.get_session_by_uuid(uuid) do
      {:ok, agent} -> agent.id
      _ -> nil
    end
  end

  defp maybe_add_tags(_task, nil), do: :ok
  defp maybe_add_tags(_task, []), do: :ok

  defp maybe_add_tags(_task, tags) do
    Enum.each(tags, fn tag_name ->
      EyeInTheSkyWeb.Tasks.get_or_create_tag(tag_name)
    end)
  end

  defp format_task(task) do
    %{
      id: task.id,
      title: task.title,
      description: task.description,
      priority: task.priority,
      state: if(Ecto.assoc_loaded?(task.state) && task.state, do: task.state.name),
      state_id: task.state_id
    }
  end
end
