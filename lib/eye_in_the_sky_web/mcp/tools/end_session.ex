defmodule EyeInTheSkyWeb.MCP.Tools.EndSession do
  @moduledoc "Complete agent session"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :agent_id, :string, required: true, description: "Agent UUID identifier"
    field :summary, :string, description: "Summary of work completed"
    field :final_status, :string, description: "Either 'completed' or 'failed' (default: completed)"
  end

  @impl true
  def execute(%{"agent_id" => agent_id} = _params, frame) do
    alias EyeInTheSkyWeb.Agents

    result =
      case Agents.get_execution_agent_by_uuid(agent_id) do
        {:ok, agent} ->
          case Agents.end_execution_agent(agent) do
            {:ok, _} -> %{success: true, message: "Session ended successfully"}
            {:error, cs} -> %{success: false, message: "Failed: #{inspect(cs.errors)}"}
          end

        {:error, :not_found} ->
          %{success: false, message: "Agent not found: #{agent_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
