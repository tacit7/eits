defmodule EyeInTheSkyWeb.NavHook do
  @moduledoc """
  LiveView on_mount hook that captures the request URI on every handle_params
  and sets deterministic mobile nav active-state assigns.

  Sets:
  - `nav_path`         — the current request path (e.g. "/projects/3/kanban")
  - `mobile_nav_tab`   — one of :sessions | :tasks | :notes | :project | :none
  - `palette_projects` — list of %{id, name} maps for the command palette

  Handles palette events for sessions, tasks, notes, and chat creation.
  Agent CRUD palette events are delegated to PaletteAgentHandlers.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.{Agents, Notes, Projects, Sessions, Tasks}
  alias EyeInTheSkyWeb.Helpers.MobileNav
  alias EyeInTheSkyWeb.NavHook.PaletteAgentHandlers

  def on_mount(:default, _params, _session, socket) do
    projects =
      Projects.list_projects()
      |> Enum.map(&%{id: &1.id, name: &1.name})

    socket =
      socket
      |> assign(:nav_path, nil)
      |> assign(:mobile_nav_tab, :sessions)
      |> assign(:palette_projects, projects)
      |> attach_hook(:capture_nav_path, :handle_params, &capture_nav_path/3)
      |> attach_hook(:palette_sessions, :handle_event, &handle_palette_event/3)
      |> attach_hook(:palette_create_task, :handle_event, &handle_create_task_event/3)
      |> attach_hook(:palette_create_note, :handle_event, &handle_create_note_event/3)
      |> attach_hook(:palette_create_chat, :handle_event, &handle_create_chat_event/3)
      |> attach_hook(:palette_create_agent, :handle_event, &PaletteAgentHandlers.handle_create_agent/3)
      |> attach_hook(:palette_update_agent, :handle_event, &PaletteAgentHandlers.handle_update_agent/3)
      |> attach_hook(:palette_list_agents, :handle_event, &PaletteAgentHandlers.handle_list_agents/3)
      |> attach_hook(:palette_get_agent, :handle_event, &PaletteAgentHandlers.handle_get_agent/3)
      |> attach_hook(:palette_delete_agent, :handle_event, &PaletteAgentHandlers.handle_delete_agent/3)

    {:cont, socket}
  end

  defp capture_nav_path(_params, url, socket) do
    path = URI.parse(url).path || "/"
    tab = MobileNav.active_tab_for_path(path)

    {:cont,
     socket
     |> assign(:nav_path, path)
     |> assign(:mobile_nav_tab, tab)}
  end

  defp handle_palette_event("palette:sessions", params, socket) do
    project_id = Projects.parse_project_id(params["project_id"])

    opts = [status_filter: "all", limit: 30]
    opts = if project_id, do: Keyword.put(opts, :project_id, project_id), else: opts

    sessions = Sessions.list_sessions_filtered(opts)

    results =
      Enum.map(sessions, fn s ->
        %{uuid: s.uuid, name: s.name, description: s.description, status: s.status}
      end)

    {:halt, push_event(socket, "palette:sessions-result", %{sessions: results})}
  end

  defp handle_palette_event(_event, _params, socket), do: {:cont, socket}

  defp handle_create_task_event("palette:create-task", params, socket) do
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

  defp handle_create_task_event(_event, _params, socket), do: {:cont, socket}

  defp handle_create_note_event("palette:create-note", params, socket) do
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

  defp handle_create_note_event(_event, _params, socket), do: {:cont, socket}

  defp handle_create_chat_event("palette:create-chat", params, socket) do
    session_uuid = params["session_uuid"]

    case Ecto.UUID.cast(session_uuid) do
      {:ok, _} -> do_create_chat(session_uuid, params, socket)
      :error -> {:halt, push_event(socket, "palette:create-chat-result", %{ok: false, error: "Invalid session UUID"})}
    end
  end

  defp handle_create_chat_event(_event, _params, socket), do: {:cont, socket}

  defp do_create_chat(session_uuid, params, socket) do
    project_id = Projects.parse_project_id(params["project_id"])

    agent_attrs = %{
      uuid: session_uuid,
      source: "manual",
      project_id: project_id
    }

    result =
      with {:ok, agent} <- Agents.find_or_create_agent(agent_attrs),
           session_attrs = %{
             uuid: session_uuid,
             agent_id: agent.id,
             name: params["name"],
             project_id: project_id,
             model_provider: "manual",
             model_name: "chat",
             status: "stopped",
             started_at: DateTime.utc_now()
           },
           {:ok, session} <- Sessions.create_session_with_model(session_attrs) do
        %{ok: true, session_uuid: session.uuid}
      else
        _ -> %{ok: false, error: "Failed to create chat"}
      end

    {:halt, push_event(socket, "palette:create-chat-result", result)}
  end
end
