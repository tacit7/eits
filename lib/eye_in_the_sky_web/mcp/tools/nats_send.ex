defmodule EyeInTheSkyWeb.MCP.Tools.NatsSend do
  @moduledoc "Send a message via NATS JetStream messaging system"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :sender_id, :string, required: true, description: "Your session_id (identifies who is sending)"
    field :receiver_id, :string, description: "Target session_id for targeted delivery. Empty = broadcast"
    field :message, :string, required: true, description: "The message content"
    field :subject, :string, description: "Message subject. Auto-prefixed with events. if not present"
  end

  @impl true
  def execute(params, frame) do
    subject = normalize_subject(params["subject"])

    payload = %{
      sender_id: params["sender_id"],
      receiver_id: params["receiver_id"] || "",
      message: params["message"],
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    result =
      case EyeInTheSkyWeb.NATS.Publisher.publish(subject, payload) do
        :ok ->
          %{success: true, message: "Message sent", subject: subject}

        {:error, reason} ->
          %{success: false, message: "NATS send failed: #{inspect(reason)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  defp normalize_subject(nil), do: "events.test"
  defp normalize_subject(""), do: "events.test"

  defp normalize_subject(subject) do
    if String.starts_with?(subject, "events."), do: subject, else: "events.#{subject}"
  end
end
