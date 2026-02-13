defmodule EyeInTheSkyWeb.Messages.Broadcaster do
  @moduledoc """
  GenServer that polls for new messages inserted by external tools (like Go MCP i-chat-send)
  and broadcasts them via Phoenix PubSub.
  """

  use GenServer
  require Logger
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Messages.Message
  import Ecto.Query

  # Poll every 1 second
  @poll_interval 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Track the last message ID we've seen
    last_id = get_latest_message_id()
    schedule_poll()
    {:ok, %{last_id: last_id}}
  end

  @impl true
  def handle_info(:poll, state) do
    # Check for new messages since last poll
    new_messages = get_new_messages_since(state.last_id)

    # Broadcast each new message
    Enum.each(new_messages, fn message ->
      broadcast_message(message)
    end)

    # Update last_id if we found new messages
    new_last_id =
      case List.last(new_messages) do
        nil -> state.last_id
        msg -> msg.id
      end

    schedule_poll()
    {:noreply, %{state | last_id: new_last_id}}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end

  defp get_latest_message_id do
    Message
    |> order_by([m], desc: m.inserted_at)
    |> limit(1)
    |> select([m], m.id)
    |> Repo.one()
  end

  defp get_new_messages_since(nil) do
    # First run - don't broadcast existing messages
    []
  end

  defp get_new_messages_since(last_id) do
    # Get messages inserted after last_id
    # Use inserted_at comparison since IDs are UUIDs (not sequential)
    last_message = Repo.get(Message, last_id)

    case last_message do
      nil ->
        # Last ID not found, might have been deleted - get recent messages
        Message
        |> where([m], not is_nil(m.channel_id))
        |> order_by([m], asc: m.inserted_at)
        |> limit(10)
        |> Repo.all()

      %Message{inserted_at: last_time} ->
        # Parse last_time if it's a string (from database)
        last_datetime =
          case last_time do
            %DateTime{} ->
              last_time

            binary when is_binary(binary) ->
              case DateTime.from_iso8601(binary) do
                {:ok, dt, _offset} -> dt
                _ -> last_time
              end

            _ ->
              last_time
          end

        Message
        |> where(
          [m],
          fragment("datetime(?) > datetime(?)", m.inserted_at, ^last_datetime) and
            not is_nil(m.channel_id)
        )
        |> order_by([m], asc: m.inserted_at)
        |> Repo.all()
    end
  end

  defp broadcast_message(%Message{channel_id: nil}), do: :ok

  defp broadcast_message(%Message{channel_id: channel_id} = message) do
    Logger.info("Broadcasting new message #{message.id} to channel #{channel_id}")

    # Broadcast to channel subscribers
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "channel:#{channel_id}:messages",
      {:new_message, message}
    )
  end
end
