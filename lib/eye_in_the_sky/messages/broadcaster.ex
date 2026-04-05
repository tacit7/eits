defmodule EyeInTheSky.Messages.Broadcaster do
  @moduledoc """
  Polls for new messages written directly to SQLite by external processes
  (Go MCP server, spawned agents, CLI tools) and broadcasts via PubSub.

  Internal Phoenix code paths (Messages.send_message, record_incoming_reply)
  already broadcast. This catches everything else. Double broadcasts are
  harmless; the LiveView handler just reloads from DB.

  Disable in test config:

      config :eye_in_the_sky, EyeInTheSky.Messages.Broadcaster, enabled: false

  Broadcasts:
    - `{:new_message, msg}` on `"session:<id>"` for session messages
    - `{:new_message, msg}` on `"channel:<id>:messages"` for channel messages
  """

  use GenServer
  require Logger
  alias EyeInTheSky.Messages.Message
  alias EyeInTheSky.Repo
  import Ecto.Query

  @poll_interval 2_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if enabled?() do
      last_id = get_max_id()
      schedule_poll()
      {:ok, %{last_id: last_id, enabled: true}}
    else
      {:ok, %{last_id: nil, enabled: false}}
    end
  end

  @impl true
  def handle_info(:poll, %{enabled: false} = state), do: {:noreply, state}

  def handle_info(:poll, state) do
    current_max = get_max_id()

    state =
      if current_max != state.last_id do
        new_messages = get_messages_after(state.last_id)
        Enum.each(new_messages, &broadcast_message/1)

        new_last =
          case List.last(new_messages) do
            nil -> current_max
            msg -> msg.id
          end

        %{state | last_id: new_last}
      else
        state
      end

    schedule_poll()
    {:noreply, state}
  end

  defp enabled? do
    Application.get_env(:eye_in_the_sky, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end

  defp get_max_id do
    case :code.is_loaded(Message) do
      false ->
        0

      _ ->
        Message
        |> select([m], max(m.id))
        |> Repo.one() || 0
    end
  end

  defp get_messages_after(last_id) when last_id in [nil, 0], do: []

  defp get_messages_after(last_id) do
    case :code.is_loaded(Message) do
      false ->
        []

      _ ->
        Message
        |> where([m], m.id > ^last_id)
        |> order_by([m], asc: m.id)
        |> limit(50)
        |> Repo.all()
    end
  end

  defp broadcast_message(%Message{session_id: sid} = msg) when not is_nil(sid) do
    EyeInTheSky.Events.session_new_message(sid, msg)

    if msg.channel_id do
      EyeInTheSky.Events.channel_message(msg.channel_id, msg)
    end
  end

  defp broadcast_message(%Message{channel_id: cid}) when not is_nil(cid) do
    EyeInTheSky.Events.channel_message(cid, %{channel_id: cid})
  end

  defp broadcast_message(_), do: :ok
end
