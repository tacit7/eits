defmodule EyeInTheSkyWeb.MCP.Tools.NatsSendRemote do
  @moduledoc "Send a message via NATS JetStream to a remote server"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :server_url, :string, required: true, description: "Remote NATS server URL"
    field :sender_id, :string, required: true, description: "Your session_id"
    field :receiver_id, :string, description: "Target session_id. Empty = broadcast"
    field :message, :string, required: true, description: "The message content"
    field :subject, :string, description: "Message subject"
  end

  @impl true
  def execute(params, frame) do
    server_url = params[:server_url]
    subject = normalize_subject(params[:subject])

    payload =
      Jason.encode!(%{
        sender_id: params[:sender_id],
        receiver_id: params[:receiver_id] || "",
        message: params[:message],
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    result =
      case Gnat.start_link(%{host: parse_host(server_url), port: parse_port(server_url)}) do
        {:ok, gnat} ->
          case Gnat.pub(gnat, subject, payload) do
            :ok ->
              Gnat.stop(gnat)
              %{success: true, message: "Message sent to remote", subject: subject}

            {:error, reason} ->
              Gnat.stop(gnat)
              %{success: false, message: "Remote publish failed: #{inspect(reason)}"}
          end

        {:error, reason} ->
          %{success: false, message: "Failed to connect to #{server_url}: #{inspect(reason)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  defp normalize_subject(nil), do: "events.test"
  defp normalize_subject(""), do: "events.test"

  defp normalize_subject(subject) do
    if String.starts_with?(subject, "events."), do: subject, else: "events.#{subject}"
  end

  defp parse_host(url) do
    url
    |> String.replace(~r{^nats://|^tls://}, "")
    |> String.split(":")
    |> List.first()
  end

  defp parse_port(url) do
    case url |> String.replace(~r{^nats://|^tls://}, "") |> String.split(":") do
      [_, port] -> String.to_integer(port)
      _ -> 4222
    end
  end
end
