defmodule EyeInTheSkyWeb.NATS.Consumer do
  @moduledoc """
  NATS connection manager and pub/sub consumer.

  Connects to NATS server, registers the connection as `:gnat`,
  subscribes to `events.>`, and dispatches messages to the Handler.
  Also relays all messages to Phoenix PubSub `"nats:events"` for the UI viewer.
  """

  use GenServer
  require Logger

  @nats_host Application.compile_env(:eye_in_the_sky_web, :nats_host, "localhost")
  @nats_port Application.compile_env(:eye_in_the_sky_web, :nats_port, 4222)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    case Gnat.start_link(%{host: @nats_host, port: @nats_port}) do
      {:ok, gnat} ->
        Process.register(gnat, :gnat)
        Logger.info("[NATS.Consumer] Connected to #{@nats_host}:#{@nats_port}")

        {:ok, _sid} = Gnat.sub(gnat, self(), "events.>")
        Logger.info("[NATS.Consumer] Subscribed to events.>")

        {:ok, %{gnat: gnat}}

      {:error, reason} ->
        Logger.error("[NATS.Consumer] Failed to connect: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:msg, %{topic: subject, body: body}}, state) do
    # Relay raw message to PubSub for NATS viewer UI
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "nats:events",
      {:nats_message, subject, body}
    )

    # Decode and dispatch to handler
    case Jason.decode(body) do
      {:ok, payload} ->
        EyeInTheSkyWeb.NATS.Handler.handle(subject, payload)

      {:error, _} ->
        Logger.warning("[NATS.Consumer] Failed to decode JSON on #{subject}: #{inspect(body)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[NATS.Consumer] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end
