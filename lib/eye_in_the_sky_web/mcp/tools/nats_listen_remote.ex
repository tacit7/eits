defmodule EyeInTheSkyWeb.MCP.Tools.NatsListenRemote do
  @moduledoc "Check for new NATS messages from a remote server"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :server_url, :string, required: true, description: "Remote NATS server URL"
    field :session_id, :string, required: true, description: "Your session ID"
    field :last_sequence, :integer, description: "Last processed sequence number"
    field :max_messages, :integer, description: "Maximum messages to fetch (default: 10)"
  end

  @impl true
  def execute(params, frame) do
    # Remote NATS listening not yet implemented in Phoenix MCP server.
    result = %{
      success: true,
      message: "Remote NATS listen not yet implemented in Phoenix MCP server",
      messages: [],
      count: 0,
      last_sequence: params[:last_sequence] || 0
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
