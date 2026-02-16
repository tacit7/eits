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
    alias EyeInTheSkyWeb.{Agents, Messages}

    # Resolve session_id: try UUID lookup first, fall back to integer string parse
    resolved_session_id = resolve_session_id(params["session_id"])

    result =
      case resolved_session_id do
        {:ok, int_id} ->
          attrs = %{
            channel_id: params["channel_id"],
            session_id: int_id,
            body: params["body"],
            sender_role: params["sender_role"] || "agent",
            recipient_role: params["recipient_role"] || "user",
            provider: params["provider"] || "claude",
            direction: "outbound",
            status: "sent"
          }

          case Messages.create_channel_message(attrs) do
            {:ok, msg} ->
              Phoenix.PubSub.broadcast(
                EyeInTheSkyWeb.PubSub,
                "channel:#{params["channel_id"]}:messages",
                {:new_message, msg}
              )

              %{success: true, message: "Message sent", message_id: to_string(msg.id)}

            {:error, cs} ->
              %{success: false, message: "Failed: #{inspect(cs.errors)}"}
          end

        {:error, reason} ->
          %{success: false, message: reason}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  defp resolve_session_id(nil), do: {:error, "session_id is required"}

  defp resolve_session_id(raw) when is_binary(raw) do
    alias EyeInTheSkyWeb.Agents

    # Try integer parse first (already resolved)
    case Integer.parse(raw) do
      {int_id, ""} ->
        {:ok, int_id}

      _ ->
        # Try UUID lookup
        case Agents.get_execution_agent_by_uuid(raw) do
          {:ok, agent} -> {:ok, agent.id}
          {:error, :not_found} -> {:error, "Session not found: #{raw}"}
        end
    end
  end

  defp resolve_session_id(id) when is_integer(id), do: {:ok, id}
end
