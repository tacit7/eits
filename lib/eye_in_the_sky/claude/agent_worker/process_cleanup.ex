defmodule EyeInTheSky.Claude.AgentWorker.ProcessCleanup do
  @moduledoc """
  Kills orphaned Claude OS processes that hold a session lock after a worker crash.

  Uses `pkill -f <uuid>` to match the UUID in the process command line.
  Session UUIDs are unique enough that false matches are extremely unlikely.
  """

  require Logger

  @doc """
  Kills any orphaned Claude process running with `uuid` in its command line.
  Sleeps 200ms after a successful kill to allow the process to fully exit
  before the caller attempts a retry.
  """
  @spec kill_orphaned(String.t()) :: :ok
  def kill_orphaned(uuid) when is_binary(uuid) do
    case System.cmd("pkill", ["-f", uuid], stderr_to_stdout: true) do
      {_, 0} ->
        Logger.info("Killed orphaned Claude process for session UUID=#{uuid}")
        # Give the process a moment to actually exit before retrying
        Process.sleep(200)

      {_, 1} ->
        # pkill exits 1 when no matching process found — not an error
        Logger.debug("No orphaned process found for session UUID=#{uuid}")

      {output, code} ->
        Logger.warning("pkill for UUID=#{uuid} exited #{code}: #{output}")
    end

    :ok
  end
end
