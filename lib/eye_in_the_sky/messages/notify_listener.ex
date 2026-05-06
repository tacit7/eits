defmodule EyeInTheSky.Messages.NotifyListener do
  use GenServer
  require Logger
  alias EyeInTheSky.{Events, Repo}
  alias EyeInTheSky.Utils.ToolHelpers
  alias EyeInTheSky.Messages.Message

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if enabled?() do
      case start_notifications() do
        {:ok, pid} ->
          {:ok, ref} = Postgrex.Notifications.listen(pid, "messages_inserted")
          {:ok, %{pid: pid, ref: ref}}

        {:error, reason} ->
          Logger.error(
            "NotifyListener: failed to start Postgrex.Notifications: #{inspect(reason)}"
          )

          :ignore
      end
    else
      :ignore
    end
  end

  @impl true
  def handle_info({:notification, _pid, _ref, "messages_inserted", payload}, state) do
    with id when is_integer(id) <- ToolHelpers.parse_int(payload),
         %Message{} = msg <- Repo.get(Message, id) do
      broadcast(msg)
    else
      _ -> :ok
    end

    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp broadcast(%Message{session_id: sid} = msg) when not is_nil(sid) do
    Events.session_new_message(sid, msg)
    if msg.channel_id, do: Events.channel_message(msg.channel_id, msg)
  end

  defp broadcast(%Message{channel_id: cid} = msg) when not is_nil(cid) do
    Events.channel_message(cid, msg)
  end

  defp broadcast(_), do: :ok

  defp start_notifications do
    Repo.config() |> Postgrex.Notifications.start_link()
  end

  defp enabled? do
    Application.get_env(:eye_in_the_sky, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end
end
