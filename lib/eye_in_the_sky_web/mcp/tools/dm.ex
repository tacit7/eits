defmodule EyeInTheSkyWeb.MCP.Tools.Dm do
  @moduledoc "Send a direct message to another agent by spawning Claude Code"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.MCP.Tools.Helpers

  schema do
    field :sender_id, :string, description: "Your session ID. Defaults to current session."
    field :target_session_id, :string, required: true, description: "Target agent's session ID"
    field :message, :string, required: true, description: "Message body to send"

    field :response_required, :boolean,
      description: "Whether response is required (default: false)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Messages
    alias EyeInTheSkyWeb.Claude.AgentManager

    sender_id = params[:sender_id] || frame.assigns[:eits_session_id]
    target_uuid = params[:target_session_id]

    result =
      case Helpers.resolve_session_int_id(target_uuid) do
        {:ok, int_id} ->
          attrs = %{
            uuid: Ecto.UUID.generate(),
            session_id: int_id,
            body: params[:message],
            sender_role: "agent",
            recipient_role: "agent",
            direction: "inbound",
            status: "delivered",
            provider: "claude",
            metadata: %{
              sender_id: sender_id,
              response_required: params[:response_required] || false
            }
          }

          with {:ok, msg} <- Messages.create_message(attrs) do
            Phoenix.PubSub.broadcast(
              EyeInTheSkyWeb.PubSub,
              "session:#{int_id}",
              {:new_dm, msg}
            )

            prompt = "[DM from session #{sender_id}]: #{params[:message]}"

            case AgentManager.send_message(int_id, prompt) do
              :ok ->
                %{success: true, message: "DM delivered to session #{int_id}"}

              {:error, reason} ->
                %{success: true, message: "DM saved but agent delivery failed: #{inspect(reason)}"}
            end
          else
            {:error, cs} -> %{success: false, message: "Failed: #{inspect(cs.errors)}"}
          end

        {:error, reason} ->
          %{success: false, message: reason}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
