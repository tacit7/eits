defmodule EyeInTheSkyWeb.MCP.Tools.NatsListen do
  @moduledoc "Check for new NATS messages in the instruction queue"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :session_id, :string,
      required: true,
      description: "Your session ID (used to filter targeted messages)"

    field :last_sequence, :integer, description: "Last processed sequence number"
    field :max_messages, :integer, description: "Maximum messages to fetch (default: 10)"
  end

  @impl true
  def execute(params, frame) do
    # NATS listening via JetStream consumer is not yet implemented in Phoenix.
    # The Go core handles this via its own NATS connection pool.
    # For now, return empty results.
    result = %{
      success: true,
      message: "NATS listen not yet implemented in Phoenix MCP server",
      messages: [],
      count: 0,
      last_sequence: params[:last_sequence] || 0
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
