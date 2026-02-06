defmodule EyeInTheSkyWeb.NATS.Publisher do
  @moduledoc """
  NATS publisher for sending messages to agents via NATS JetStream.
  """

  require Logger

  @doc """
  Publishes a message to NATS for agent processing.

  Message format follows the eits-messaging-v1 protocol:
  - Subject: events.chat for user messages
  - Payload: JSON envelope with op, channel, version, msg fields
  """
  def publish_message(message, opts \\ []) do
    connection = Keyword.get(opts, :connection, get_connection())

    # Build envelope following eits-messaging-v1 protocol
    envelope = %{
      op: "msg",
      channel: "chat",
      version: "eits-messaging-v1",
      reply_to: message.session_id,
      msg: message.body,
      meta: %{
        message_id: message.id,
        provider: message.provider,
        timestamp: format_timestamp(message.inserted_at)
      }
    }

    payload = Jason.encode!(envelope)

    case Gnat.pub(connection, "events.chat", payload) do
      :ok ->
        Logger.info("Published message #{message.id} to NATS events.chat")
        {:ok, message}

      {:error, reason} ->
        Logger.error("Failed to publish message #{message.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Publishes a message to a channel for multi-agent consumption.

  Message format follows the eits-messaging-v2 protocol:
  - Subject: events.channel.{channel_id}
  - Payload: JSON envelope with channel_id, parent_message_id (optional for threads)
  """
  def publish_channel_message(message, channel_id, opts \\ []) do
    connection = Keyword.get(opts, :connection, get_connection())

    # Build envelope following eits-messaging-v2 protocol
    envelope = %{
      op: "msg",
      channel: "chat",
      version: "eits-messaging-v2",
      channel_id: channel_id,
      parent_message_id: message.parent_message_id,
      msg: message.body,
      meta: %{
        message_id: message.id,
        sender_session_id: message.session_id,
        provider: message.provider,
        timestamp: format_timestamp(message.inserted_at),
        attachments: format_attachments(message)
      }
    }

    payload = Jason.encode!(envelope)
    subject = "events.channel.#{channel_id}"

    case Gnat.pub(connection, subject, payload) do
      :ok ->
        Logger.info("Published channel message #{message.id} to #{subject}")
        {:ok, message}

      {:error, reason} ->
        Logger.error("Failed to publish channel message #{message.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Publishes a direct message to a specific agent by session_id.

  Message format follows the eits-messaging-v3 protocol:
  - Subject: events.direct.{session_id}
  - Payload: JSON envelope with target_session_id and message
  """
  def publish_direct_message(message, target_session_id, opts \\ []) do
    connection = Keyword.get(opts, :connection, get_connection())

    # Build envelope following eits-messaging-v3 protocol
    envelope = %{
      op: "msg",
      channel: "direct",
      version: "eits-messaging-v3",
      target_session_id: target_session_id,
      msg: message.body,
      meta: %{
        message_id: message.id,
        sender_session_id: message.session_id,
        provider: message.provider,
        timestamp: format_timestamp(message.inserted_at)
      }
    }

    payload = Jason.encode!(envelope)
    subject = "events.direct.#{target_session_id}"

    case Gnat.pub(connection, subject, payload) do
      :ok ->
        Logger.info("Published direct message #{message.id} to #{subject}")
        {:ok, message}

      {:error, reason} ->
        Logger.error("Failed to publish direct message #{message.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Broadcasts a message to all agents (empty receiver_id).
  """
  def broadcast_message(body, opts \\ []) do
    connection = Keyword.get(opts, :connection, get_connection())

    envelope = %{
      op: "msg",
      channel: "protocol",
      version: "eits-messaging-v1",
      msg: body
    }

    payload = Jason.encode!(envelope)

    case Gnat.pub(connection, "events.protocol", payload) do
      :ok ->
        Logger.info("Broadcast message to NATS events.protocol")
        :ok

      {:error, reason} ->
        Logger.error("Failed to broadcast message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp format_attachments(message) do
    case Map.get(message, :attachments) do
      %Ecto.Association.NotLoaded{} ->
        []

      attachments when is_list(attachments) ->
        Enum.map(attachments, fn att ->
          %{
            id: att.id,
            filename: att.original_filename,
            size: att.size_bytes,
            content_type: att.content_type
          }
        end)

      _ ->
        []
    end
  end

  defp format_timestamp(nil), do: DateTime.utc_now() |> DateTime.to_iso8601()
  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp format_timestamp(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
  end

  defp format_timestamp(timestamp) when is_binary(timestamp), do: timestamp
  defp format_timestamp(_), do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp get_connection do
    case Process.whereis(:gnat) do
      nil ->
        Logger.error("NATS connection not found")
        nil

      pid ->
        pid
    end
  end
end
