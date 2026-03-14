defmodule EyeInTheSkyWeb.MCP.Tools.SessionInfo do
  @moduledoc "Show current session state: agent_id, session_id, project_id stored on this MCP server process"

  use Anubis.Server.Component, type: :tool

  alias EyeInTheSkyWeb.MCP.Tools.ResponseHelper
  alias EyeInTheSkyWeb.Sessions

  schema do
    field :session_id, :string, description: "Session UUID to look up"
  end

  @impl true
  def execute(params, frame) do
    uuid = params[:session_id]

    result =
      if uuid do
        case Sessions.get_session_by_uuid(uuid) do
          {:ok, session} ->
            agent_uuid = resolve_agent_uuid(session.agent_id)

            %{
              agent_id: agent_uuid,
              session_id: uuid,
              project_id: session.project_id,
              status: session.status,
              initialized: true
            }

          {:error, :not_found} ->
            %{agent_id: nil, session_id: uuid, initialized: false}
        end
      else
        %{agent_id: nil, session_id: nil, initialized: false}
      end

    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end

  defp resolve_agent_uuid(nil), do: nil

  defp resolve_agent_uuid(agent_int_id) do
    alias EyeInTheSkyWeb.Agents

    case Agents.get_agent(agent_int_id) do
      {:ok, agent} -> agent.uuid
      _ -> nil
    end
  end
end
