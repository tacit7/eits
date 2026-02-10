defmodule EyeInTheSkyWeb.NATS.Consumer do
  @moduledoc """
  NATS consumer GenServer. Manages the Gnat connection (registered as :gnat)
  and relays pub/sub messages to the Phoenix PubSub "nats:events" topic
  for the NATS viewer UI. All business logic lives in JetStreamConsumer.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    nats_config = Application.get_env(:eye_in_the_sky_web, :nats, [])
    host = Keyword.get(nats_config, :host, "localhost")
    port = Keyword.get(nats_config, :port, 4222)

    {:ok, conn} =
      Gnat.start_link(%{
        host: host,
        port: port
      })

    Process.register(conn, :gnat)

    {:ok, _sub} = Gnat.sub(conn, self(), "events.>")

    Logger.info("NATS Consumer started, subscribed to events.> (pub/sub relay only)")

    {:ok, %{conn: conn}}
  end

  @impl true
  def handle_info({:msg, %{topic: topic, body: body}}, state) do
    Logger.debug("Received NATS pub/sub message on #{topic}")

    case Jason.decode(body) do
      {:ok, decoded} ->
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "nats:events",
          {:nats_message, topic, decoded}
        )

      {:error, _reason} ->
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "nats:events",
          {:nats_message, topic, body}
        )
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{conn: conn}) do
    Gnat.stop(conn)
    :ok
  end
end
