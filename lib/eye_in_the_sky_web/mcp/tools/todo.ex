defmodule EyeInTheSkyWeb.MCP.Tools.Todo do
  @moduledoc "Task management. Commands: create, annotate, start, done, status, tag, list, list-agent, list-session, list-team, search, delete, add-session, remove-session, add-session-to-tasks"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.MCP.Tools.Helpers

  schema do
    field :command, :string, required: true, description: "Command to execute"
    field :task_id, :string, description: "Task ID"
    field :task_ids, {:list, :string}, description: "List of task IDs (for add-session-to-tasks)"
    field :title, :string, description: "Task title (for create)"
    field :description, :string, description: "Task description"
    field :priority, :integer, description: "Task priority"
    field :state_id, :integer, description: "Workflow state ID"
    field :project_id, :integer, description: "Project ID"
    field :team_id, :integer, description: "Team ID (for list-team or scoping tasks to a team)"
    field :agent_id, :string, description: "Agent ID"
    field :session_id, :string, description: "Session ID"
    field :query, :string, description: "Search query"
    field :tags, {:list, :string}, description: "Tags to add"
    field :body, :string, description: "Note body (for annotate)"
    field :due_at, :string, description: "Due date (ISO 8601)"
    field :limit, :integer, description: "Result limit"
  end

  @impl true
  def execute(%{command: "create"} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    attrs = %{
      uuid: Ecto.UUID.generate(),
      title: params[:title],
      description: params[:description],
      priority: params[:priority],
      state_id: params[:state_id] || 1,
      project_id: params[:project_id],
      team_id: params[:team_id],
      agent_id: resolve_agent_int_id(params[:agent_id]),
      due_at: params[:due_at],
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    frame_session_id = if is_struct(frame), do: frame.assigns[:eits_session_id], else: nil
    session_id = params[:session_id] || frame_session_id

    resolved_project_id =
      params[:project_id] ||
        case frame_session_id && EyeInTheSkyWeb.Sessions.get_session_by_uuid(frame_session_id) do
          {:ok, session} -> session.project_id
          _ -> nil
        end

    attrs = Map.put(attrs, :project_id, resolved_project_id)

    result =
      case Tasks.create_task(attrs) do
        {:ok, task} ->
          maybe_add_tags(task, params[:tags])
          maybe_link_session(task.id, session_id)
          %{success: true, message: "Task created", task_id: to_string(task.id)}

        {:error, cs} ->
          %{success: false, message: "Failed: #{inspect(cs.errors)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "list"} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    tasks =
      cond do
        params[:team_id] -> Tasks.list_tasks_for_team(params[:team_id])
        params[:project_id] -> EyeInTheSkyWeb.Projects.get_project_tasks(params[:project_id])
        true -> Tasks.list_tasks()
      end

    limit = params[:limit] || 50
    tasks = Enum.take(tasks, limit)

    result = %{
      success: true,
      message: "#{length(tasks)} task(s)",
      tasks: Enum.map(tasks, &format_task/1)
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "list-team"} = params, frame) do
    alias EyeInTheSkyWeb.{Tasks, Teams}

    team =
      cond do
        params[:team_id] -> Teams.get_team(params[:team_id])
        true -> nil
      end

    result =
      case team do
        nil ->
          %{success: false, message: "team_id required"}

        team ->
          tasks = Tasks.list_tasks_for_team(team.id)
          limit = params[:limit] || 100
          tasks = Enum.take(tasks, limit)
          %{success: true, team_id: team.id, team_name: team.name, tasks: Enum.map(tasks, &format_task/1)}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "list-agent"} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    agent_id = resolve_agent_int_id(params[:agent_id])
    tasks = if agent_id, do: Tasks.list_tasks_for_agent(agent_id), else: []

    result = %{
      success: true,
      message: "#{length(tasks)} task(s) for agent",
      tasks: Enum.map(tasks, &format_task/1)
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "list-session"} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    session_int_id =
      case Helpers.resolve_session_int_id(params[:session_id]) do
        {:ok, id} -> id
        {:error, _} -> nil
      end

    tasks = if session_int_id, do: Tasks.list_tasks_for_session(session_int_id), else: []

    result = %{
      success: true,
      message: "#{length(tasks)} task(s) for session",
      tasks: Enum.map(tasks, &format_task/1)
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "search"} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    query = params[:query] || ""
    tasks = Tasks.search_tasks(query)
    limit = params[:limit] || 50
    tasks = Enum.take(tasks, limit)

    result = %{
      success: true,
      message: "Found #{length(tasks)} task(s)",
      tasks: Enum.map(tasks, &format_task/1)
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "done", task_id: task_id}, frame) do
    update_task_state(task_id, "Done", frame)
  end

  def execute(%{command: "start", task_id: task_id}, frame) do
    update_task_state(task_id, "In Progress", frame)
  end

  def execute(%{command: "status", task_id: task_id} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    result =
      try do
        task = Tasks.get_task!(task_id)

        update_attrs =
          %{}
          |> then(fn m ->
            if params[:state_id], do: Map.put(m, :state_id, params[:state_id]), else: m
          end)
          |> then(fn m ->
            if params[:priority], do: Map.put(m, :priority, params[:priority]), else: m
          end)

        case Tasks.update_task(task, update_attrs) do
          {:ok, _} -> %{success: true, message: "Task updated"}
          {:error, cs} -> %{success: false, message: "Failed: #{inspect(cs.errors)}"}
        end
      rescue
        Ecto.NoResultsError -> %{success: false, message: "Task not found: #{task_id}"}
        Ecto.Query.CastError -> %{success: false, message: "Invalid task_id: #{task_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "delete", task_id: task_id}, frame) do
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
        Ecto.Query.CastError -> %{success: false, message: "Invalid task_id: #{task_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "annotate", task_id: task_id} = params, frame) do
    alias EyeInTheSkyWeb.Notes

    result =
      case Notes.create_note(%{
             parent_id: task_id,
             parent_type: "task",
             body: params[:body] || "",
             title: params[:title]
           }) do
        {:ok, note} -> %{success: true, message: "Annotation added", note_id: note.id}
        {:error, cs} -> %{success: false, message: "Failed: #{inspect(cs.errors)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "tag", task_id: task_id} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    result =
      try do
        task = Tasks.get_task!(task_id)
        tags = params[:tags] || []
        Enum.each(tags, fn tag_name -> Tasks.get_or_create_tag(tag_name) end)
        %{success: true, message: "Tags updated for task #{task.id}"}
      rescue
        Ecto.NoResultsError -> %{success: false, message: "Task not found: #{task_id}"}
        Ecto.Query.CastError -> %{success: false, message: "Invalid task_id: #{task_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "add-session", task_id: task_id} = params, frame) do
    result =
      case params[:session_id] do
        nil ->
          %{success: false, message: "session_id required"}

        session_id ->
          maybe_link_session(task_id, session_id)
          %{success: true, message: "Session linked to task #{task_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "remove-session", task_id: task_id} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    result =
      case {task_id, params[:session_id]} do
        {nil, _} ->
          %{success: false, message: "task_id required"}

        {_, nil} ->
          %{success: false, message: "session_id required"}

        {tid, sid} ->
          task_int_id = parse_int_id(tid)

          session_int_id =
            case Helpers.resolve_session_int_id(sid) do
              {:ok, id} -> id
              {:error, _} -> nil
            end

          if task_int_id && session_int_id do
            count = Tasks.unlink_session_from_task(task_int_id, session_int_id)
            %{success: true, message: "Unlinked session from task (#{count} row(s) removed)"}
          else
            %{success: false, message: "Could not resolve task_id or session_id"}
          end
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: "add-session-to-tasks"} = params, frame) do
    alias EyeInTheSkyWeb.Tasks

    result =
      case {params[:session_id], params[:task_ids]} do
        {nil, _} ->
          %{success: false, message: "session_id required"}

        {_, nil} ->
          %{success: false, message: "task_ids required"}

        {_, []} ->
          %{success: false, message: "task_ids must not be empty"}

        {sid, task_ids} ->
          case Helpers.resolve_session_int_id(sid) do
            {:ok, session_int_id} ->
              linked =
                Enum.count(task_ids, fn tid ->
                  case parse_int_id(tid) do
                    nil ->
                      false

                    task_int_id ->
                      Tasks.link_session_to_task(task_int_id, session_int_id)
                      true
                  end
                end)

              %{success: true, message: "Session linked to #{linked}/#{length(task_ids)} task(s)"}

            {:error, reason} ->
              %{success: false, message: reason}
          end
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: cmd}, frame)
      when cmd in ["reindex", "vacuum", "project-sync"] do
    result = %{
      success: false,
      message:
        "Command '#{cmd}' is not supported. These are DB maintenance operations not available at the tool level."
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  def execute(%{command: cmd}, frame) do
    result = %{success: false, message: "Unknown command: #{cmd}"}
    response = Response.tool() |> Response.json(result)
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
        Ecto.Query.CastError -> %{success: false, message: "Invalid task_id: #{task_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  defp maybe_link_session(_task_id, nil), do: :ok

  defp maybe_link_session(task_id, session_id) when is_binary(session_id) do
    alias EyeInTheSkyWeb.Tasks

    case Helpers.resolve_session_int_id(session_id) do
      {:ok, int_id} ->
        task_int_id = parse_int_id(task_id)
        if task_int_id, do: Tasks.link_session_to_task(task_int_id, int_id)

      {:error, _} ->
        :ok
    end
  end

  defp parse_int_id(id) when is_integer(id), do: id

  defp parse_int_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp resolve_agent_int_id(nil), do: nil

  defp resolve_agent_int_id(uuid) do
    alias EyeInTheSkyWeb.Sessions

    case Sessions.get_session_by_uuid(uuid) do
      {:ok, session} -> session.agent_id
      _ -> nil
    end
  end

  defp maybe_add_tags(_task, nil), do: :ok
  defp maybe_add_tags(_task, []), do: :ok

  defp maybe_add_tags(task, tags) do
    alias EyeInTheSkyWeb.Tasks

    Enum.each(tags, fn tag_name ->
      case Tasks.get_or_create_tag(tag_name) do
        {:ok, tag} -> Tasks.link_tag_to_task(task.id, tag.id)
        _ -> :ok
      end
    end)
  end

  defp format_task(task) do
    %{
      id: task.id,
      title: task.title,
      description: task.description,
      priority: task.priority,
      state: if(Ecto.assoc_loaded?(task.state) && task.state, do: task.state.name),
      state_id: task.state_id,
      team_id: Map.get(task, :team_id)
    }
  end
end
