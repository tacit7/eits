defmodule EyeInTheSkyWeb.MCP.Tools.Dm do
  @moduledoc "Send a direct message to another agent by spawning Claude Code"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :sender_id, :string, required: true, description: "Your session ID"
    field :target_session_id, :string, required: true, description: "Target agent's session ID"
    field :message, :string, required: true, description: "Message body to send"
    field :response_required, :boolean, description: "Whether response is required (default: false)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Messages

    # Store the DM as a message
    attrs = %{
      session_id: params["target_session_id"],
      body: params["message"],
      sender_role: "agent",
      recipient_role: "agent",
      direction: "inbound",
      status: "pending",
      metadata: %{
        sender_id: params["sender_id"],
        response_required: params["response_required"] || false
      }
    }

    result =
      case Messages.create_message(attrs) do
        {:ok, _msg} ->
          # Broadcast so DmLive picks it up
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "dm:#{params["target_session_id"]}",
            {:new_dm, params["message"]}
          )

          %{success: true, message: "DM delivered to #{params["target_session_id"]}"}

        {:error, cs} ->
          %{success: false, message: "Failed: #{inspect(cs.errors)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
