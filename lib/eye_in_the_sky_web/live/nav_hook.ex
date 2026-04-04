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

  alias EyeInTheSky.{Agents, Notes, Sessions, Projects, Tasks, Repo}
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
      |> attach_hook(:palette_update_agent, :handle_event, &handle_update_agent_event/3)
      |> attach_hook(:palette_list_agents, :handle_event, &handle_list_agents_event/3)
      |> attach_hook(:palette_get_agent, :handle_event, &handle_get_agent_event/3)
      |> attach_hook(:palette_delete_agent, :handle_event, &handle_delete_agent_event/3)

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

    case Ecto.UUID.cast(session_uuid) do
      {:ok, _} -> do_create_chat(session_uuid, params, socket)
      :error -> {:halt, push_event(socket, "palette:create-chat-result", %{ok: false, error: "Invalid session UUID"})}
    end
  end

  defp handle_create_chat_event(_event, _params, socket), do: {:cont, socket}

  defp handle_create_agent_event("palette:create-agent", params, socket) do
    instructions = String.trim(params["instructions"] || "")
    parent_session_uuid = params["parent_session_uuid"]

    cond do
      instructions == "" ->
        {:halt, push_event(socket, "palette:create-agent-result", %{ok: false, error: "Instructions are required"})}

      parent_session_uuid not in [nil, ""] ->
        # Validate parent session exists before proceeding
        case Sessions.get_session_by_uuid(parent_session_uuid) do
          {:ok, _parent_session} ->
            do_create_agent(instructions, params, socket)

          {:error, :not_found} ->
            {:halt, push_event(socket, "palette:create-agent-result",
              %{ok: false, error: "Parent session UUID does not exist"})}
        end

      true ->
        do_create_agent(instructions, params, socket)
    end
  end

  defp handle_create_agent_event(_event, _params, socket), do: {:cont, socket}

  defp handle_update_agent_event("palette:update-agent", params, socket) do
    agent_uuid = String.trim(params["agent_uuid"] || "")
    instructions = String.trim(params["instructions"] || "")

    cond do
      agent_uuid == "" ->
        {:halt, push_event(socket, "palette:update-agent-result", %{ok: false, error: "Agent UUID is required"})}

      instructions == "" ->
        {:halt, push_event(socket, "palette:update-agent-result", %{ok: false, error: "Instructions are required"})}

      true ->
        # Update-agent feature validates inputs but cannot update running agents
        # as instructions are not stored and cannot be changed mid-execution
        {:halt, push_event(socket, "palette:update-agent-result",
          %{ok: false, error: "Cannot update instructions for running agents"})}
    end
  end

  defp handle_update_agent_event(_event, _params, socket), do: {:cont, socket}

  defp handle_list_agents_event("palette:list-agents", params, socket) do
    project_id = Projects.parse_project_id(params["project_id"])

    agents =
      if project_id do
        Agents.list_agents_by_project(project_id)
      else
        Agents.list_agents_with_sessions()
      end

    # Map agents to include name, UUID, status, and session count
    results =
      Enum.map(agents, fn agent ->
        # Get the latest session status if sessions are preloaded
        latest_status =
          case agent do
            %{sessions: [session | _]} -> session.status
            _ -> "no_sessions"
          end

        # Count sessions if preloaded
        session_count =
          case agent do
            %{sessions: sessions} when is_list(sessions) -> length(sessions)
            _ -> 0
          end

        %{
          id: agent.id,
          uuid: agent.uuid,
          name: agent.description || "Agent #{agent.id}",
          status: latest_status,
          session_count: session_count
        }
      end)

    {:halt, push_event(socket, "palette:list-agents-result", %{agents: results})}
  end

  defp handle_list_agents_event(_event, _params, socket), do: {:cont, socket}

  defp handle_get_agent_event("palette:get-agent", params, socket) do
    agent_uuid = String.trim(params["agent_uuid"] || "")

    if agent_uuid == "" do
      {:halt, push_event(socket, "palette:get-agent-result", %{ok: false, error: "Agent UUID is required"})}
    else
      case Agents.get_agent_by_uuid(agent_uuid) do
        {:ok, agent} ->
          # Preload sessions to get count and latest status
          agent = Repo.preload(agent, [:sessions, :project])

          # Get the latest session status
          latest_status =
            case agent.sessions do
              [session | _] -> session.status
              _ -> "no_sessions"
            end

          # Get instructions if stored (though currently not in schema)
          # For now, instructions would come from agent_definitions if linked
          instructions =
            case agent do
              %{agent_definition_id: def_id} when not is_nil(def_id) ->
                # Could fetch from agent_definitions table if needed
                nil
              _ ->
                nil
            end

          result = %{
            ok: true,
            agent: %{
              uuid: agent.uuid,
              name: agent.description || "Agent #{agent.id}",
              status: latest_status,
              session_count: length(agent.sessions || []),
              instructions: instructions,
              project_name: agent.project && agent.project.name,
              created_at: agent.created_at
            }
          }

          {:halt, push_event(socket, "palette:get-agent-result", result)}

        {:error, :not_found} ->
          {:halt, push_event(socket, "palette:get-agent-result", %{ok: false, error: "Agent not found"})}
      end
    end
  end

  defp handle_get_agent_event(_event, _params, socket), do: {:cont, socket}

  defp handle_delete_agent_event("palette:delete-agent", params, socket) do
    agent_uuid = String.trim(params["agent_uuid"] || "")

    if agent_uuid == "" do
      {:halt, push_event(socket, "palette:delete-agent-result", %{ok: false, error: "Agent UUID is required"})}
    else
      case Agents.get_agent_by_uuid(agent_uuid) do
        {:ok, agent} ->
          # Preload sessions to check for active ones
          agent = Repo.preload(agent, :sessions)

          # Check for active sessions (working or idle statuses)
          active_sessions =
            Enum.filter(agent.sessions || [], fn session ->
              session.status in ["working", "idle"]
            end)

          if active_sessions != [] do
            {:halt, push_event(socket, "palette:delete-agent-result",
              %{ok: false, error: "Cannot delete agent with active sessions (#{length(active_sessions)} active)"})}
          else
            # Delete the agent
            case Agents.delete_agent(agent) do
              {:ok, _deleted} ->
                {:halt, push_event(socket, "palette:delete-agent-result", %{ok: true})}

              {:error, _reason} ->
                {:halt, push_event(socket, "palette:delete-agent-result",
                  %{ok: false, error: "Failed to delete agent"})}
            end
          end

        {:error, :not_found} ->
          {:halt, push_event(socket, "palette:delete-agent-result", %{ok: false, error: "Agent not found"})}
      end
    end
  end

  defp handle_delete_agent_event(_event, _params, socket), do: {:cont, socket}

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

  defp do_create_agent(instructions, params, socket) do
    project_id = Projects.parse_project_id(params["project_id"])
    parent_session_uuid = params["parent_session_uuid"]

    project_path =
      if project_id do
        case Projects.get_project(project_id) do
          %{path: path} -> path
          _ -> nil
        end
      end

    # Convert parent_session_uuid to parent_session_id if provided
    parent_session_id =
      if parent_session_uuid not in [nil, ""] do
        case Sessions.get_session_by_uuid(parent_session_uuid) do
          {:ok, parent_session} -> parent_session.id
          _ -> nil
        end
      end

    opts = [
      instructions: instructions,
      model: params["model"] || "haiku",
      project_id: project_id,
      project_path: project_path,
      parent_session_id: parent_session_id
    ]

    result =
      case AgentManager.create_agent(opts) do
        {:ok, %{session: session}} -> %{ok: true, session_uuid: session.uuid}
        {:error, _} -> %{ok: false, error: "Failed to spawn agent"}
      end

    {:halt, push_event(socket, "palette:create-agent-result", result)}
  end

end
