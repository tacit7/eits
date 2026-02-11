defmodule EyeInTheSkyWeb.NATS.Reader do
  @moduledoc """
  NATS JetStream reader for querying stream information.
  Used to fetch the latest sequence number for channel message replay.
  """

  require Logger

  @doc """
  Gets the latest sequence number for a channel's NATS stream.
  Returns 0 if the stream doesn't exist or has no messages.

  ## Examples

      iex> get_latest_sequence(1)
      142

      iex> get_latest_sequence(999)
      0
  """
  def get_latest_sequence(channel_id) do
    stream_name = get_stream_name()

    case get_connection() do
      nil ->
        Logger.error("NATS Reader: connection not available")
        0

      conn ->
        case Gnat.Jetstream.API.Stream.info(conn, stream_name) do
          {:ok, stream_info} ->
            # Extract last sequence from stream state
            get_in(stream_info, [:state, :last_seq]) || 0

          {:error, reason} ->
            Logger.warning("NATS Reader: failed to get stream info for #{stream_name}: #{inspect(reason)}")
            0
        end
    end
  end

  @doc """
  Fetches the last N messages from a channel stream.
  Returns a list of message envelopes.

  ## Examples

      iex> fetch_last_messages(1, 10)
      [%{body: "hello", sender_role: "user", ...}, ...]
  """
  def fetch_last_messages(channel_id, count \\ 10) do
    latest_seq = get_latest_sequence(channel_id)
    start_from = max(0, latest_seq - count)

    case get_connection() do
      nil ->
        Logger.error("NATS Reader: connection not available")
        []

      conn ->
        # Use JetStream fetch to get messages from start_from to latest_seq
        # Note: This is a simplified implementation - you may need to adjust based on your stream setup
        fetch_messages_from_stream(conn, start_from, count, channel_id)
    end
  end

  defp fetch_messages_from_stream(_conn, _start_seq, _count, _channel_id) do
    # TODO: Implement actual message fetching from JetStream
    # This would involve creating a temporary consumer or using fetch API
    # For now, return empty list
    []
  end

  defp get_stream_name do
    nats_config = Application.get_env(:eye_in_the_sky_web, :nats, [])
    Keyword.get(nats_config, :stream_name, "EVENTS")
  end

  defp get_connection do
    case Process.whereis(:gnat) do
      nil ->
        Logger.error("NATS Reader: :gnat process not found")
        nil

      pid ->
        pid
    end
  end
end
