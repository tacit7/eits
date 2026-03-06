defmodule EyeInTheSkyWeb.Claude.ChatManager do
  @moduledoc """
  Manages ChatWorker lifecycle — one per channel.

  Ensures a ChatWorker is running for a channel before routing messages.
  Call `send_to_channel/4` from ChatLive instead of calling AgentManager directly.
  """

  require Logger

  alias EyeInTheSkyWeb.Claude.ChatWorker

  @registry EyeInTheSkyWeb.Claude.ChatRegistry
  @supervisor EyeInTheSkyWeb.Claude.ChatSupervisor

  @doc """
  Sends `message` to all channel members except `sender_session_id`.
  Starts a ChatWorker for the channel if one isn't already running.
  """
  def send_to_channel(channel_id, message, sender_session_id, opts \\ [])
      when is_binary(message) do
    case lookup_or_start(channel_id) do
      {:ok, _pid} ->
        ChatWorker.send_to_channel(channel_id, message, sender_session_id, opts)

      {:error, reason} ->
        Logger.error(
          "ChatManager: failed to start worker for channel=#{channel_id} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # --- Private ---

  defp lookup_or_start(channel_id) do
    case Registry.lookup(@registry, {:channel, channel_id}) do
      [{pid, _}] ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          start_worker(channel_id)
        end

      [] ->
        start_worker(channel_id)
    end
  end

  defp start_worker(channel_id) do
    opts = [channel_id: channel_id]

    case DynamicSupervisor.start_child(@supervisor, {ChatWorker, opts}) do
      {:ok, pid} = result ->
        Logger.info("ChatManager: started ChatWorker for channel=#{channel_id} pid=#{inspect(pid)}")
        result

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error(
          "ChatManager: failed to start ChatWorker for channel=#{channel_id} reason=#{inspect(reason)}"
        )

        error
    end
  end
end
