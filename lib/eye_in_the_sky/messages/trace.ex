defmodule EyeInTheSky.Messages.Trace do
  @moduledoc """
  Generates and propagates `message_trace_id` values used to correlate a
  single message's journey across logs, telemetry, and PubSub events.
  """

  require Logger

  @type trace_id :: String.t()

  @doc "Generates a new short trace id (not a UUID — these appear in log lines)."
  @spec new() :: trace_id
  def new do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
  end

  @doc "Attaches trace_id to the Logger metadata for the current process."
  @spec set_in_logger(trace_id) :: :ok
  def set_in_logger(trace_id) when is_binary(trace_id) do
    Logger.metadata(message_trace_id: trace_id)
    :ok
  end
end
