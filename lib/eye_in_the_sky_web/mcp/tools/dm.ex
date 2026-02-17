defmodule EyeInTheSkyWeb.MCP.Tools.Dm do
  @moduledoc "Send a direct message to another agent by spawning Claude Code"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.Sessions

  schema do
    field :sender_id, :string, required: true, description: "Your session ID"
    field :target_session_id, :string, required: true, description: "Target agent's session ID"
    field :message, :string, required: true, description: "Message body to send"

    field :response_required, :boolean,
      description: "Whether response is required (default: false)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Messages

    target_uuid = params["target_session_id"]

    # Resolve UUID to internal integer session_id
    result =
      case Sessions.get_session_by_uuid(target_uuid) do
        {:ok, agent} ->
          attrs = %{
            session_id: agent.id,
            body: params["message"],
            sender_role: "agent",
            recipient_role: "agent",
            direction: "inbound",
            status: "delivered",
            provider: "claude",
            metadata: %{
              sender_id: params["sender_id"],
              response_required: params["response_required"] || false
            }
          }

          case Messages.create_message(attrs) do
            {:ok, msg} ->
              # Broadcast on the topics DmLive subscribes to
              Phoenix.PubSub.broadcast(
                EyeInTheSkyWeb.PubSub,
                "session:#{agent.id}",
                {:new_dm, msg}
              )

              %{success: true, message: "DM delivered to session #{agent.id}"}

            {:error, cs} ->
              %{success: false, message: "Failed: #{inspect(cs.errors)}"}
          end

        {:error, :not_found} ->
          %{success: false, message: "Target session not found: #{target_uuid}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
