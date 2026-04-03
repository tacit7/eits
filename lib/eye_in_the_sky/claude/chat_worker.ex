defmodule EyeInTheSky.Claude.ChatWorker do
  @moduledoc """
  Persistent per-channel GenServer that fans out messages to all channel members.

  One ChatWorker per channel. When a message is sent, it routes to every member
  session via AgentManager.send_message. Manages a queue of pending messages;
  when busy (fan-out in progress), queues new messages and processes them
  sequentially. Mirrors AgentWorker's queue/retry/error handling.
  """

  use GenServer
  require Logger

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Claude.ChannelProtocol
  alias EyeInTheSky.Channels

  @registry EyeInTheSky.Claude.ChatRegistry

  # --- Client API ---

  def start_link(opts) do
    channel_id = Keyword.fetch!(opts, :channel_id)
    name = {:via, Registry, {@registry, {:channel, channel_id}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Send `message` to all members of `channel_id`, skipping `sender_session_id`.
  If the worker is busy, the message is queued.
  """
  def send_to_channel(channel_id, message, sender_session_id, opts \\ []) do
    case Registry.lookup(@registry, {:channel, channel_id}) do
      [{pid, _}] ->
        GenServer.cast(pid, {:send_to_channel, message, sender_session_id, opts})

      [] ->
        {:error, :not_found}
    end
  end

  def is_processing?(channel_id) do
    case Registry.lookup(@registry, {:channel, channel_id}) do
      [{pid, _}] -> GenServer.call(pid, :is_processing?)
      [] -> false
    end
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    channel_id = Keyword.fetch!(opts, :channel_id)

    state = %{
      channel_id: channel_id,
      processing: false,
      queue: []
    }

    Logger.info("ChatWorker started for channel=#{channel_id}")

    {:ok, state}
  end

  @impl true
  def handle_call(:is_processing?, _from, state) do
    {:reply, state.processing, state}
  end

  @impl true
  def handle_cast({:send_to_channel, message, sender_session_id, opts}, state)
      when is_binary(message) do
    job = %{
      message: message,
      sender_session_id: sender_session_id,
      opts: opts,
      queued_at: DateTime.utc_now()
    }

    if state.processing do
      new_len = length(state.queue) + 1

      Logger.info(
        "ChatWorker: busy, queueing message for channel=#{state.channel_id} queue_length=#{new_len}"
      )

      {:noreply, enqueue_job(state, job)}
    else
      Logger.info("ChatWorker: processing message for channel=#{state.channel_id}")
      {:noreply, process_job(%{state | processing: true}, job)}
    end
  end

  def handle_cast({:send_to_channel, message, _sender, _opts}, state) do
    Logger.warning(
      "ChatWorker: invalid message payload for channel=#{state.channel_id} message=#{inspect(message)}"
    )

    {:noreply, state}
  end

  # Fan-out complete — process next queued job or go idle
  @impl true
  def handle_info({:fanout_complete, results}, state) do
    log_results(results, state.channel_id)
    process_next_job(%{state | processing: false})
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in ChatWorker: #{inspect(msg)}")
    {:noreply, state}
  end

  # --- Private ---

  defp process_job(state, job) do
    worker = self()

    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      results = fanout(state.channel_id, job.message, job.sender_session_id, job.opts)
      send(worker, {:fanout_complete, results})
    end)

    state
  end

  defp fanout(channel_id, message, sender_session_id, opts) do
    members = Channels.list_members(channel_id)

    members
    |> Enum.reject(fn m -> ChannelProtocol.skip?(m.session_id, sender_session_id) end)
    |> Enum.map(fn member ->
      {mode, _mentioned_ids, _mention_all} =
        ChannelProtocol.parse_routing(message, member.session_id)

      prompt = ChannelProtocol.build_prompt(mode, message)

      result =
        try do
          AgentManager.send_message(member.session_id, prompt, opts)
        rescue
          e ->
            Logger.error(
              "ChatWorker: exception routing to session=#{member.session_id} - #{inspect(e)}"
            )

            {:error, {:exception, e}}
        end

      case result do
        {:ok, admission} ->
          Logger.info(
            "ChatWorker: routed to session=#{member.session_id} channel=#{channel_id} mode=#{mode} admission=#{admission}"
          )

        {:error, reason} ->
          Logger.error(
            "ChatWorker: failed to route to session=#{member.session_id} channel=#{channel_id} reason=#{inspect(reason)}"
          )
      end

      {member.session_id, result}
    end)
  end

  defp process_next_job(%{queue: []} = state) do
    {:noreply, state}
  end

  defp process_next_job(%{queue: [next | rest]} = state) do
    Logger.info("ChatWorker: processing next queued message for channel=#{state.channel_id}")
    {:noreply, process_job(%{state | processing: true, queue: rest}, next)}
  end

  defp enqueue_job(state, job), do: %{state | queue: state.queue ++ [job]}

  defp log_results(results, channel_id) do
    ok_count = Enum.count(results, fn {_, r} -> match?(:ok, r) or match?({:ok, _}, r) end)
    err_count = length(results) - ok_count

    Logger.info(
      "ChatWorker: fan-out complete channel=#{channel_id} ok=#{ok_count} errors=#{err_count}"
    )
  end
end
