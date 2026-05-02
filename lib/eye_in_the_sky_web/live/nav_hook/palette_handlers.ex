defmodule EyeInTheSkyWeb.NavHook.PaletteHandlers do
  @moduledoc """
  Palette event handlers for sessions, tasks, notes, and chat creation.

  Extracted from NavHook to keep the nav hook focused on navigation state.
  Each public function is attached as a `handle_event` hook in NavHook.on_mount/4.
  """

  require Logger

  import Phoenix.LiveView, only: [push_event: 3]

  alias EyeInTheSky.{Agents, Notes, Projects, Sessions, Tasks}

  # ---------------------------------------------------------------------------
  # palette:sessions
  # ---------------------------------------------------------------------------

  def handle_palette_event("palette:sessions", params, socket) do
    project_id = Projects.parse_project_id(params["project_id"])

    opts = [status_filter: "all", limit: 30]
    opts = if project_id, do: Keyword.put(opts, :project_id, project_id), else: opts

    sessions = Sessions.list_sessions_filtered(opts)

    results =
      Enum.map(sessions, fn s ->
        %{id: s.id, uuid: s.uuid, name: s.name, description: s.description, status: s.status}
      end)

    {:halt, push_event(socket, "palette:sessions-result", %{sessions: results})}
  end

  # ---------------------------------------------------------------------------
  # palette:recent-sessions
  # ---------------------------------------------------------------------------

  def handle_palette_event("palette:recent-sessions", _params, socket) do
    sessions = Sessions.list_sessions_filtered(status_filter: "all", sort_by: :last_activity, limit: 15)

    results =
      Enum.map(sessions, fn s ->
        %{id: s.id, uuid: s.uuid, name: s.name, description: s.description, status: s.status}
      end)

    {:halt, push_event(socket, "palette:recent-sessions-result", %{sessions: results})}
  end

  # ---------------------------------------------------------------------------
  # palette:tasks
  # ---------------------------------------------------------------------------

  def handle_palette_event("palette:tasks", params, socket) do
    project_id = Projects.parse_project_id(params["project_id"])

    tasks =
      if project_id do
        Tasks.list_tasks_for_project(project_id, limit: 20)
      else
        Tasks.list_tasks(limit: 20)
      end

    results =
      Enum.map(tasks, fn t ->
        %{id: t.id, title: t.title, state_id: t.state_id, state_name: t.state && t.state.name, project_id: t.project_id}
      end)

    {:halt, push_event(socket, "palette:tasks-result", %{tasks: results})}
  end

  # ---------------------------------------------------------------------------
  # palette:notes
  # ---------------------------------------------------------------------------

  def handle_palette_event("palette:notes", params, socket) do
    project_id = Projects.parse_project_id(params["project_id"])

    opts = [sort: "newest", limit: 20]
    opts = if project_id, do: Keyword.put(opts, :project_id, project_id), else: opts

    notes = Notes.list_notes_filtered(opts)

    results =
      Enum.map(notes, fn n ->
        title =
          if n.title && n.title != "" do
            n.title
          else
            n.body |> String.slice(0, 60)
          end

        %{id: n.id, title: title, parent_type: n.parent_type, parent_id: n.parent_id}
      end)

    {:halt, push_event(socket, "palette:notes-result", %{notes: results})}
  end

  # ---------------------------------------------------------------------------
  # palette:projects
  # ---------------------------------------------------------------------------

  def handle_palette_event("palette:projects", _params, socket) do
    projects = Projects.list_projects()

    results =
      Enum.map(projects, fn p ->
        %{id: p.id, name: p.name}
      end)

    {:halt, push_event(socket, "palette:projects-result", %{projects: results})}
  end

  def handle_palette_event(_event, _params, socket), do: {:cont, socket}

  # ---------------------------------------------------------------------------
  # palette:create-task
  # ---------------------------------------------------------------------------

  def handle_create_task_event("palette:create-task", params, socket) do
    project_id = Projects.parse_project_id(params["project_id"])
    tags = params["tags"]

    title = params["title"] || ""
    description = params["description"] || ""
    tags_string = if(is_list(tags), do: Enum.join(tags, ","), else: tags || "")

    tag_names =
      tags_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    now = DateTime.utc_now()

    task_attrs = %{
      uuid: Ecto.UUID.generate(),
      title: title,
      description: description,
      state_id: Tasks.WorkflowState.todo_id(),
      priority: 1,
      created_at: now,
      updated_at: now
    }

    task_attrs = if project_id, do: Map.put(task_attrs, :project_id, project_id), else: task_attrs

    result =
      case Tasks.create_task(task_attrs) do
        {:ok, task} ->
          if tag_names != [], do: Tasks.replace_task_tags(task.id, tag_names)
          %{ok: true}

        {:error, _changeset} ->
          %{ok: false, error: "Failed to create task"}
      end

    {:halt, push_event(socket, "palette:create-task-result", result)}
  end

  def handle_create_task_event(_event, _params, socket), do: {:cont, socket}

  # ---------------------------------------------------------------------------
  # palette:create-note
  # ---------------------------------------------------------------------------

  def handle_create_note_event("palette:create-note", params, socket) do
    attrs = %{
      title: params["title"] || "",
      body: params["body"] || "(empty)",
      parent_type: "system",
      parent_id: "0"
    }

    result =
      case Notes.create_note(attrs) do
        {:ok, _note} -> %{ok: true}
        {:error, _} -> %{ok: false, error: "Failed to create note"}
      end

    {:halt, push_event(socket, "palette:create-note-result", result)}
  end

  def handle_create_note_event(_event, _params, socket), do: {:cont, socket}

  # ---------------------------------------------------------------------------
  # palette:create-chat
  # ---------------------------------------------------------------------------

  def handle_create_chat_event("palette:create-chat", params, socket) do
    session_uuid = params["session_uuid"]

    case Ecto.UUID.cast(session_uuid) do
      {:ok, _} ->
        do_create_chat(session_uuid, params, socket)

      :error ->
        {:halt,
         push_event(socket, "palette:create-chat-result", %{
           ok: false,
           error: "Invalid session UUID"
         })}
    end
  end

  def handle_create_chat_event(_event, _params, socket), do: {:cont, socket}

  defp do_create_chat(session_uuid, params, socket) do
    project_id = Projects.parse_project_id(params["project_id"])

    agent_attrs = %{
      uuid: session_uuid,
      source: "manual",
      project_id: project_id
    }

    result =
      with {:agent, {:ok, agent}} <- {:agent, Agents.find_or_create_agent(agent_attrs)},
           session_attrs = %{
             uuid: session_uuid,
             agent_id: agent.id,
             name: params["name"],
             project_id: project_id,
             model_provider: "manual",
             model_name: "chat",
             status: "idle",
             started_at: DateTime.utc_now()
           },
           {:session, {:ok, session}} <-
             {:session, Sessions.create_session_with_model(session_attrs)} do
        %{ok: true, session_uuid: session.uuid}
      else
        {:agent, {:error, reason}} ->
          Logger.warning("palette create-chat: agent creation failed: #{inspect(reason)}")
          %{ok: false, error: "Failed to create agent"}

        {:session, {:error, reason}} ->
          Logger.warning("palette create-chat: session creation failed: #{inspect(reason)}")
          %{ok: false, error: "Failed to create session"}
      end

    {:halt, push_event(socket, "palette:create-chat-result", result)}
  end
end
