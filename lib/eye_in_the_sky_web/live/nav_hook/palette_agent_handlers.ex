defmodule EyeInTheSkyWeb.NavHook.PaletteAgentHandlers do
  @moduledoc """
  Palette event handlers for agent CRUD operations.

  Extracted from NavHook to keep the nav hook focused on navigation state.
  Each public function is attached as a `handle_event` hook in NavHook.on_mount/4.
  """

  import Phoenix.LiveView, only: [push_event: 3]

  alias EyeInTheSky.{Agents, Sessions, Projects, Repo}
  alias EyeInTheSky.Agents.AgentManager

  # ---------------------------------------------------------------------------
  # palette:create-agent
  # ---------------------------------------------------------------------------

  def handle_create_agent("palette:create-agent", params, socket) do
    instructions = String.trim(params["instructions"] || "")
    parent_session_uuid = params["parent_session_uuid"]

    cond do
      instructions == "" ->
        {:halt,
         push_event(socket, "palette:create-agent-result", %{
           ok: false,
           error: "Instructions are required"
         })}

      parent_session_uuid not in [nil, ""] ->
        case Sessions.get_session_by_uuid(parent_session_uuid) do
          {:ok, _} ->
            do_create_agent(instructions, params, socket)

          {:error, :not_found} ->
            {:halt,
             push_event(socket, "palette:create-agent-result", %{
               ok: false,
               error: "Parent session UUID does not exist"
             })}
        end

      true ->
        do_create_agent(instructions, params, socket)
    end
  end

  def handle_create_agent(_event, _params, socket), do: {:cont, socket}

  # ---------------------------------------------------------------------------
  # palette:update-agent
  # ---------------------------------------------------------------------------

  def handle_update_agent("palette:update-agent", params, socket) do
    agent_uuid = String.trim(params["agent_uuid"] || "")
    instructions = String.trim(params["instructions"] || "")

    cond do
      agent_uuid == "" ->
        {:halt,
         push_event(socket, "palette:update-agent-result", %{
           ok: false,
           error: "Agent UUID is required"
         })}

      instructions == "" ->
        {:halt,
         push_event(socket, "palette:update-agent-result", %{
           ok: false,
           error: "Instructions are required"
         })}

      true ->
        {:halt,
         push_event(socket, "palette:update-agent-result", %{
           ok: false,
           error: "Cannot update instructions for running agents"
         })}
    end
  end

  def handle_update_agent(_event, _params, socket), do: {:cont, socket}

  # ---------------------------------------------------------------------------
  # palette:list-agents
  # ---------------------------------------------------------------------------

  def handle_list_agents("palette:list-agents", params, socket) do
    project_id = Projects.parse_project_id(params["project_id"])

    agents =
      if project_id do
        Agents.list_agents_by_project(project_id)
      else
        Agents.list_agents_with_sessions()
      end

    results =
      Enum.map(agents, fn agent ->
        latest_status =
          case agent do
            %{sessions: [session | _]} -> session.status
            _ -> "no_sessions"
          end

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

  def handle_list_agents(_event, _params, socket), do: {:cont, socket}

  # ---------------------------------------------------------------------------
  # palette:get-agent
  # ---------------------------------------------------------------------------

  def handle_get_agent("palette:get-agent", params, socket) do
    agent_uuid = String.trim(params["agent_uuid"] || "")

    if agent_uuid == "" do
      {:halt,
       push_event(socket, "palette:get-agent-result", %{
         ok: false,
         error: "Agent UUID is required"
       })}
    else
      case Agents.get_agent_by_uuid(agent_uuid) do
        {:ok, agent} ->
          agent = Repo.preload(agent, [:sessions, :project])

          latest_status =
            case agent.sessions do
              [session | _] -> session.status
              _ -> "no_sessions"
            end

          result = %{
            ok: true,
            agent: %{
              uuid: agent.uuid,
              name: agent.description || "Agent #{agent.id}",
              status: latest_status,
              session_count: length(agent.sessions || []),
              instructions: nil,
              project_name: agent.project && agent.project.name,
              created_at: agent.created_at
            }
          }

          {:halt, push_event(socket, "palette:get-agent-result", result)}

        {:error, :not_found} ->
          {:halt,
           push_event(socket, "palette:get-agent-result", %{
             ok: false,
             error: "Agent not found"
           })}
      end
    end
  end

  def handle_get_agent(_event, _params, socket), do: {:cont, socket}

  # ---------------------------------------------------------------------------
  # palette:delete-agent
  # ---------------------------------------------------------------------------

  def handle_delete_agent("palette:delete-agent", params, socket) do
    agent_uuid = String.trim(params["agent_uuid"] || "")

    if agent_uuid == "" do
      {:halt,
       push_event(socket, "palette:delete-agent-result", %{
         ok: false,
         error: "Agent UUID is required"
       })}
    else
      case Agents.get_agent_by_uuid(agent_uuid) do
        {:ok, agent} ->
          agent = Repo.preload(agent, :sessions)

          active_sessions =
            Enum.filter(agent.sessions || [], fn session ->
              session.status in ["working", "idle"]
            end)

          if active_sessions != [] do
            {:halt,
             push_event(socket, "palette:delete-agent-result", %{
               ok: false,
               error:
                 "Cannot delete agent with active sessions (#{length(active_sessions)} active)"
             })}
          else
            case Agents.delete_agent(agent) do
              {:ok, _} ->
                {:halt, push_event(socket, "palette:delete-agent-result", %{ok: true})}

              {:error, _} ->
                {:halt,
                 push_event(socket, "palette:delete-agent-result", %{
                   ok: false,
                   error: "Failed to delete agent"
                 })}
            end
          end

        {:error, :not_found} ->
          {:halt,
           push_event(socket, "palette:delete-agent-result", %{
             ok: false,
             error: "Agent not found"
           })}
      end
    end
  end

  def handle_delete_agent(_event, _params, socket), do: {:cont, socket}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

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
