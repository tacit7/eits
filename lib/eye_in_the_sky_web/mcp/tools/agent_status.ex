defmodule EyeInTheSkyWeb.MCP.Tools.AgentStatus do
  @moduledoc "Check whether an agent worker is currently processing by session ID (int or UUID)"

  use Anubis.Server.Component, type: :tool

  alias EyeInTheSkyWeb.MCP.Tools.ResponseHelper
  alias EyeInTheSkyWeb.MCP.Tools.Helpers

  schema do
    field :session_id, :string,
      required: true,
      description: "Target session ID (integer or UUID)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Claude.AgentWorker

    result =
      case Helpers.resolve_session_int_id(params[:session_id]) do
        {:ok, int_id} ->
          processing = AgentWorker.is_processing?(int_id)
          # is_processing? returns false when worker not found, so also check registry
          alive = worker_alive?(int_id)

          cond do
            not alive ->
              %{success: true, session_id: int_id, status: "no_worker", processing: false}

            processing ->
              %{success: true, session_id: int_id, status: "processing", processing: true}

            true ->
              %{success: true, session_id: int_id, status: "idle", processing: false}
          end

        {:error, reason} ->
          %{success: false, message: reason}
      end

    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end

  defp worker_alive?(session_id) do
    registry = EyeInTheSkyWeb.Claude.AgentRegistry

    case Registry.lookup(registry, {:agent, session_id}) do
      [{pid, _}] -> Process.alive?(pid)
      [] -> false
    end
  end
end
