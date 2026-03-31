defmodule EyeInTheSkyWeb.NavHook do
  @moduledoc """
  LiveView on_mount hook that captures the request URI on every handle_params
  and sets deterministic mobile nav active-state assigns.

  Sets:
  - `nav_path`         — the current request path (e.g. "/projects/3/kanban")
  - `mobile_nav_tab`   — one of :sessions | :tasks | :notes | :project | :none
  - `palette_projects` — list of %{id, name} maps for the command palette

  Also handles the `palette:sessions` event for the command palette's
  "Go to Session..." submenu, so every LiveView in the :app live_session
  can serve session data over the socket without an HTTP API call.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.{Agents, Notes, Sessions, Projects, Tasks}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSkyWeb.Helpers.MobileNav

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
      |> attach_hook(:palette_create_agent, :handle_event, &handle_create_agent_event/3)

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
    project_id = parse_project_id(params["project_id"])

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
    project_id = parse_project_id(params["project_id"])
    tags = params["tags"]

    form_params = %{
      "title" => params["title"] || "",
      "description" => params["description"] || "",
      "state_id" => "1",
      "tags" => if(is_list(tags), do: Enum.join(tags, ","), else: tags || "")
    }

    opts = if project_id, do: [project_id: project_id], else: []

    result =
      case Tasks.create_task_from_form(form_params, opts) do
        {:ok, _task} -> %{ok: true}
        {:error, _changeset} -> %{ok: false, error: "Failed to create task"}
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
    project_id = parse_project_id(params["project_id"])

    agent_attrs = %{
      uuid: session_uuid,
      source: "manual",
      project_id: project_id
    }

    result =
      with {:ok, agent} <- find_or_create_agent(agent_attrs),
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

  defp handle_create_chat_event(_event, _params, socket), do: {:cont, socket}

  defp handle_create_agent_event("palette:create-agent", params, socket) do
    project_id = parse_project_id(params["project_id"])

    project_path =
      if project_id do
        case Projects.get_project(project_id) do
          %{path: path} -> path
          _ -> nil
        end
      end

    opts = [
      instructions: params["instructions"] || "",
      model: params["model"] || "haiku",
      project_id: project_id,
      project_path: project_path
    ]

    result =
      case AgentManager.create_agent(opts) do
        {:ok, %{session: session}} -> %{ok: true, session_uuid: session.uuid}
        {:error, _} -> %{ok: false, error: "Failed to spawn agent"}
      end

    {:halt, push_event(socket, "palette:create-agent-result", result)}
  end

  defp handle_create_agent_event(_event, _params, socket), do: {:cont, socket}

  defp find_or_create_agent(%{uuid: uuid} = attrs) do
    case Agents.get_agent_by_uuid(uuid) do
      {:ok, existing} -> {:ok, existing}
      {:error, :not_found} -> Agents.create_agent(attrs)
    end
  end

  defp parse_project_id(nil), do: nil
  defp parse_project_id(id) when is_integer(id), do: id

  defp parse_project_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_project_id(_), do: nil
end
