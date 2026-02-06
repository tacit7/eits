#!/usr/bin/env elixir

# Test agent script that listens for messages and sends automated replies
# Usage: elixir priv/scripts/test_agent.exs

Mix.install([
  {:gnat, "~> 1.8"},
  {:jason, "~> 1.2"}
])

defmodule TestAgent do
  require Logger

  def start do
    Logger.configure(level: :info)
    Logger.info("Test Agent starting...")

    # Connect to NATS
    {:ok, conn} = Gnat.start_link(%{host: "localhost", port: 4222})
    Logger.info("Connected to NATS at localhost:4222")

    # Subscribe to events.chat
    {:ok, _sub} = Gnat.sub(conn, self(), "events.chat")
    Logger.info("Subscribed to events.chat")

    loop(conn)
  end

  defp loop(conn) do
    receive do
      {:msg, %{body: body, reply_to: reply_to}} ->
        Logger.info("Received message: #{body}")

        case Jason.decode(body) do
          {:ok, envelope} ->
            handle_message(conn, envelope)

          {:error, reason} ->
            Logger.error("Failed to decode message: #{inspect(reason)}")
        end

        loop(conn)
    end
  end

  defp handle_message(conn, %{"op" => "msg", "channel" => "chat"} = envelope) do
    user_message = envelope["msg"]
    session_id = envelope["reply_to"]
    provider = get_in(envelope, ["meta", "provider"]) || "claude"

    Logger.info("User said: #{user_message}")

    # Generate a simple response
    response = generate_response(user_message, provider)

    # Build reply envelope
    reply_envelope = %{
      op: "msg",
      channel: "chat",
      version: "eits-messaging-v1",
      reply_to: session_id,
      msg: response,
      meta: %{
        provider: provider,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    payload = Jason.encode!(reply_envelope)

    # Publish reply
    case Gnat.pub(conn, "events.chat", payload) do
      :ok ->
        Logger.info("Sent reply: #{response}")

      {:error, reason} ->
        Logger.error("Failed to send reply: #{inspect(reason)}")
    end
  end

  defp handle_message(_conn, envelope) do
    Logger.debug("Unhandled envelope: #{inspect(envelope)}")
  end

  defp generate_response(message, provider) do
    responses = [
      "I received your message: \"#{message}\". How can I help you further?",
      "Thanks for your message! I'm processing that now.",
      "Interesting question! Let me think about that...",
      "I understand. Could you provide more details?",
      "Great point! Here's what I think about #{message}...",
      "Processing your request via #{provider}..."
    ]

    Enum.random(responses)
  end
end

TestAgent.start()
