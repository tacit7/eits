defmodule EyeInTheSky.Agents.CmdDispatcher.Helpers do
  @moduledoc """
  Shared helpers for CmdDispatcher subcommand handlers.

  Provides notify_success/2, notify_error/3, extract_flag/2, get_session!/1,
  put_optional_flag/4, and with_task/3 — a common wrapper that eliminates the
  repeated `rescue Ecto.NoResultsError` pattern across task subcommands.
  """

  require Logger

  alias EyeInTheSky.{Notifications, Sessions}
  alias EyeInTheSky.Agents.AgentManager

  @doc """
  Sends a success acknowledgement back to the originating agent session.
  """
  def notify_success(from_session_id, msg) do
    Logger.info("[CmdDispatcher] #{msg}")

    if from_session_id do
      Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
        AgentManager.send_message(from_session_id, "[EITS-CMD ok] #{msg}")
      end)
    end

    :ok
  end

  @doc """
  Logs the error, creates a persistent notification, and DMs the error back
  to the originating agent session.
  """
  def notify_error(from_session_id, cmd, reason) do
    msg = "[EITS-CMD error] #{cmd}: #{inspect(reason)}"
    Logger.warning("[CmdDispatcher] #{msg}")

    Notifications.notify("EITS-CMD #{cmd} failed",
      body: inspect(reason),
      category: :agent,
      resource: {"session", to_string(from_session_id)}
    )

    if from_session_id do
      Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
        AgentManager.send_message(from_session_id, msg)
      end)
    end

    :ok
  end

  @doc """
  Resolves a session by ID, returning nil on failure (non-raising).
  """
  def get_session!(session_id) do
    case Sessions.get_session(session_id) do
      {:ok, session} -> session
      _ -> nil
    end
  end

  @doc """
  Adds a flag to opts if the named flag is present in args string.
  """
  def put_optional_flag(opts, args, flag, key) do
    case extract_flag(args, flag) do
      {:ok, value} -> Keyword.put(opts, key, value)
      _ -> opts
    end
  end

  @doc """
  Wraps a task lookup + execution, converting Ecto.NoResultsError into
  a notify_error call. Eliminates the repeated rescue block pattern.

  Usage:
      with_task(id_str, from_session_id, "task done", fn id, task ->
        Tasks.update_task_state(task, 3)
        notify_success(from_session_id, "task \#{id} -> done")
      end)
  """
  def with_task(id_str, from_session_id, cmd, fun) when is_binary(id_str) do
    case Integer.parse(String.trim(id_str)) do
      {id, ""} ->
        task = EyeInTheSky.Tasks.get_task!(id)
        fun.(id, task)

      _ ->
        notify_error(from_session_id, cmd, {:invalid_id, id_str})
    end
  rescue
    Ecto.NoResultsError -> notify_error(from_session_id, cmd, :not_found)
  end

  @doc """
  Handles: --flag "quoted value"  or  --flag multi word value (to next flag or EOL).
  """
  def extract_flag(str, flag) do
    escaped = Regex.escape(flag)

    case Regex.run(~r/#{escaped}\s+"([^"]*)"/, str) do
      [_, value] ->
        {:ok, value}

      nil ->
        case Regex.run(~r/#{escaped}\s+(.+?)(?=\s+--\S|\z)/s, str) do
          [_, value] -> {:ok, String.trim(value)}
          nil -> {:error, {:missing_flag, flag}}
        end
    end
  end
end
