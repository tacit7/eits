defmodule EyeInTheSkyWeb.MCP.Tools.EndSession do
  @moduledoc "Complete agent session"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.Sessions

  schema do
    field :session_id, :string, required: true, description: "Session UUID (Claude Code session ID)"
    field :summary, :string, description: "Summary of work completed"

    field :final_status, :string,
      description: "Either 'completed' or 'failed' (default: completed)"
  end

  @impl true
  def execute(%{session_id: session_id} = params, frame) do
    session_uuid = session_id

    opts =
      %{}
      |> then(fn m -> if params[:summary], do: Map.put(m, :summary, params[:summary]), else: m end)
      |> then(fn m -> if params[:final_status], do: Map.put(m, :final_status, params[:final_status]), else: m end)

    result =
      case Sessions.get_session_by_uuid(session_uuid) do
        {:ok, session} ->
          case Sessions.end_session(session, opts) do
            {:ok, _} -> %{success: true, message: "Session ended successfully"}
            {:error, cs} -> %{success: false, message: "Failed: #{inspect(cs.errors)}"}
          end

        {:error, :not_found} ->
          %{success: false, message: "Session not found: #{session_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
