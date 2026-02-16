defmodule EyeInTheSkyWeb.MCP.Tools.ChatSend do
  @moduledoc "Send a message directly to a chat channel"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :channel_id, :string, required: true, description: "Channel ID to send message to"
    field :session_id, :string, required: true, description: "Session ID of the sender"
    field :body, :string, required: true, description: "Message body text"
    field :sender_role, :string, description: "Sender role (default: 'agent')"
    field :recipient_role, :string, description: "Recipient role (default: 'user')"
    field :provider, :string, description: "Provider name (default: 'claude')"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Messages

    attrs = %{
      channel_id: params["channel_id"],
      session_id: params["session_id"],
      body: params["body"],
      sender_role: params["sender_role"] || "agent",
      recipient_role: params["recipient_role"] || "user",
      provider: params["provider"] || "claude",
      direction: "outbound",
      status: "sent"
    }

    result =
      case Messages.create_channel_message(attrs) do
        {:ok, msg} ->
          # Broadcast via PubSub so LiveViews update
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "channel:#{params["channel_id"]}",
            {:new_message, msg}
          )

          %{success: true, message: "Message sent", message_id: to_string(msg.id)}

        {:error, cs} ->
          %{success: false, message: "Failed: #{inspect(cs.errors)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
