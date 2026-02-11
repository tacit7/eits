defmodule EyeInTheSkyWeb.NATS.JetStreamConsumer do
  @moduledoc """
  Durable JetStream pull consumer for the EVENTS stream.
  Uses Gnat.Jetstream.PullConsumer behavior with server-side cursor tracking.
  Handles all business logic: channel messages, DM delivery, dedup.
  """

  use Gnat.Jetstream.PullConsumer
  require Logger

  alias EyeInTheSkyWeb.Messages

  def start_link(_opts) do
    config = nats_config()
    stream = Keyword.get(config, :stream_name, "EVENTS")
    consumer = Keyword.get(config, :consumer_name, "eits-web")

    with :ok <- wait_for_gnat(),
         :ok <- ensure_consumer_exists() do
      Logger.info("JetStreamConsumer: starting pull consumer on #{stream}/#{consumer}")
      Gnat.Jetstream.PullConsumer.start_link(__MODULE__, [], name: __MODULE__)
    end
  end

  @impl true
  def init(_state) do
    Logger.info("JetStreamConsumer: initializing")
    config = nats_config()

    connection_options = [
      connection_name: :gnat,
      stream_name: Keyword.get(config, :stream_name, "EVENTS"),
      consumer_name: Keyword.get(config, :consumer_name, "eits-web")
    ]

    {:ok, %{}, connection_options}
  end

  @impl true
  def handle_message(message, state) do
    body = message.body

    case decode_body(body) do
      {:ok, decoded} when is_map(decoded) ->
        topic = message.topic || message[:subject] || "unknown"

        # Broadcast to NATS page UI
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "nats:events",
          {:nats_message, topic, decoded}
        )

        process_decoded(decoded, topic)

      _ ->
        Logger.warning("JetStreamConsumer: could not decode message body")
    end

    {:ack, state}
  end

  # --- Startup helpers ---

  defp wait_for_gnat(retries \\ 10) do
    case Process.whereis(:gnat) do
      nil when retries > 0 ->
        Logger.debug("JetStreamConsumer: waiting for :gnat process (#{retries} retries left)")
        Process.sleep(500)
        wait_for_gnat(retries - 1)

      nil ->
        Logger.error("JetStreamConsumer: :gnat process not found after retries")
        {:error, :gnat_not_found}

      _pid ->
        :ok
    end
  end

  defp ensure_consumer_exists do
    config = nats_config()
    stream = Keyword.get(config, :stream_name, "EVENTS")
    consumer = Keyword.get(config, :consumer_name, "eits-web")
    filter = Keyword.get(config, :filter_subject, "events.>")

    case Gnat.Jetstream.API.Consumer.info(:gnat, stream, consumer) do
      {:ok, _info} ->
        Logger.info("JetStreamConsumer: durable consumer #{consumer} exists")
        :ok

      {:error, _} ->
        Logger.info("JetStreamConsumer: creating durable consumer #{consumer}")

        consumer_config = %Gnat.Jetstream.API.Consumer{
          stream_name: stream,
          durable_name: consumer,
          filter_subject: filter,
          ack_policy: :explicit,
          deliver_policy: :new
        }

        case Gnat.Jetstream.API.Consumer.create(:gnat, consumer_config) do
          {:ok, _} ->
            Logger.info("JetStreamConsumer: consumer #{consumer} created")
            :ok

          {:error, reason} ->
            Logger.error("JetStreamConsumer: failed to create consumer: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp nats_config do
    Application.get_env(:eye_in_the_sky_web, :nats, [])
  end

  # --- Body decoding ---

  @doc false
  def decode_body(body) when is_binary(body) do
    # Try base64 first, then raw JSON
    case Base.decode64(body) do
      {:ok, decoded_bytes} ->
        case Jason.decode(decoded_bytes) do
          {:ok, json} -> {:ok, json}
          _ -> Jason.decode(body)
        end

      :error ->
        Jason.decode(body)
    end
  end

  @doc false
  def decode_body(_), do: {:error, :not_binary}

  # --- Message routing ---

  @doc false
  def process_decoded(decoded, topic) do
    case decoded do
      %{"op" => "msg", "channel" => "chat", "version" => "eits-messaging-v2"} ->
        handle_v2_channel_message(decoded)

      %{"op" => "msg", "channel" => "chat"} ->
        handle_v1_session_message(decoded)

      %{"op" => "ack"} ->
        Logger.debug("JetStreamConsumer: received ACK: #{inspect(decoded)}")

      _ ->
        maybe_handle_dm(decoded, topic)
    end
  end

  # --- V2 channel messages ---

  defp handle_v2_channel_message(envelope) do
    message_id = get_in(envelope, ["meta", "message_id"])
    channel_id = envelope["channel_id"]

    if message_id && Messages.message_exists?(message_id) do
      Logger.debug("JetStreamConsumer: duplicate v2 message #{message_id}, broadcasting to UI")

      # Fetch existing message and broadcast to UI
      case Messages.get_message(message_id) do
        {:ok, message} ->
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "channel:#{channel_id}:messages",
            {:new_message, message}
          )
        _ ->
          :ok
      end
    else
      parent_message_id = envelope["parent_message_id"]
      sender_session_id = get_in(envelope, ["meta", "sender_session_id"])
      provider = get_in(envelope, ["meta", "provider"]) || "unknown"
      message_body = envelope["msg"]

      attrs = %{
        id: message_id || Ecto.UUID.generate(),
        channel_id: channel_id,
        parent_message_id: parent_message_id,
        session_id: sender_session_id,
        sender_role: "agent",
        recipient_role: "user",
        provider: provider,
        direction: "inbound",
        body: message_body,
        status: "delivered",
        metadata: %{}
      }

      case Messages.create_message(attrs) do
        {:ok, message} ->
          Logger.info("JetStreamConsumer: recorded v2 channel message #{message.id}")

          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "channel:#{channel_id}:messages",
            {:new_message, message}
          )

        {:error, reason} ->
          Logger.error("JetStreamConsumer: failed to record v2 message: #{inspect(reason)}")
      end
    end
  end

  # --- V1 session messages ---

  defp handle_v1_session_message(envelope) do
    message_id = get_in(envelope, ["meta", "message_id"])

    if message_id && Messages.message_exists?(message_id) do
      Logger.debug("JetStreamConsumer: skipping duplicate v1 message #{message_id}")
    else
      session_id = envelope["reply_to"]
      provider = get_in(envelope, ["meta", "provider"]) || "unknown"
      message_body = envelope["msg"]

      case Messages.record_incoming_reply(session_id, provider, message_body) do
        {:ok, message} ->
          Logger.info("JetStreamConsumer: recorded v1 message #{message.id}")

          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "session:#{session_id}:messages",
            {:new_message, message}
          )

        {:error, reason} ->
          Logger.error("JetStreamConsumer: failed to record v1 message: #{inspect(reason)}")
      end
    end
  end

  # --- DM handling with dedup ---

  defp maybe_handle_dm(data, _topic) do
    receiver_id =
      data["receiver_id"] || data["receiver"] || data["receiverId"] ||
        get_in(data, ["meta", "receiver_id"])

    sender_id =
      data["sender_id"] || data["sender"] || data["senderId"] ||
        get_in(data, ["meta", "sender_id"])

    message_text =
      data["message"] || data["msg"] || data["body"] || inspect(data)

    if receiver_id && receiver_id != "" do
      broadcast_to_dm(receiver_id, sender_id, message_text, data)
    end
  end

  defp broadcast_to_dm(session_id, sender_id, message_text, envelope) do
    dedup_id = compute_dedup_id(envelope, sender_id, session_id, message_text)

    if Messages.message_exists?(dedup_id) do
      Logger.debug("JetStreamConsumer: skipping duplicate DM #{dedup_id}")
    else
      attrs = %{
        id: dedup_id,
        session_id: session_id,
        sender_role: "agent",
        recipient_role: "user",
        provider: "nats",
        direction: "inbound",
        body: "[NATS from #{sender_id}] #{message_text}",
        status: "delivered",
        metadata: %{}
      }

      case Messages.create_message(attrs) do
        {:ok, _message} ->
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "session:#{session_id}",
            {:nats_message_for_agent, message_text}
          )

          Logger.info("JetStreamConsumer: delivered DM to session #{session_id}")

        {:error, reason} ->
          Logger.error("JetStreamConsumer: failed to deliver DM to #{session_id}: #{inspect(reason)}")
      end
    end
  end

  @doc false
  def compute_dedup_id(envelope, sender_id, receiver_id, body) do
    # Prefer explicit message_id from envelope metadata
    explicit_id =
      get_in(envelope, ["meta", "message_id"]) ||
        envelope["message_id"] ||
        envelope["id"]

    case explicit_id do
      nil ->
        # Compute SHA256-based dedup ID
        :crypto.hash(:sha256, "#{sender_id}:#{receiver_id}:#{body}")
        |> Base.encode16(case: :lower)
        |> String.slice(0, 36)

      id ->
        id
    end
  end
end
