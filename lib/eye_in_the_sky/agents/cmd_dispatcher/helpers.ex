defmodule EyeInTheSky.Agents.CmdDispatcher.Helpers do
  @moduledoc """
  Shared helpers for CmdDispatcher subcommand handlers.

  Provides notify_success/2, notify_error/3, extract_flag/2, get_session!/1,
  session_field/2, put_optional_flag/4, and with_task/4 — a common wrapper
  that handles task lookup with proper tagged-tuple error handling.
  """

  require Logger

  alias EyeInTheSky.{Notifications, Sessions}
  alias EyeInTheSky.Utils.ToolHelpers

  def notify_success(_from_session_id, msg) do
    Logger.info("[CmdDispatcher] #{msg}")
    :ok
  end

  def notify_error(from_session_id, cmd, reason) do
    msg = "[EITS-CMD error] #{cmd}: #{inspect(reason)}"
    Logger.warning("[CmdDispatcher] #{msg}")

    Notifications.notify("EITS-CMD #{cmd} failed",
      body: inspect(reason),
      category: :agent,
      resource: {"session", to_string(from_session_id)}
    )

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
  Safely reads a field from a session struct that may be nil.
  Returns nil if session is nil; otherwise returns the field value.
  """
  def session_field(nil, _key), do: nil
  def session_field(session, key), do: Map.get(session, key)

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
  Wraps a task lookup + execution, handling {:error, :not_found} from
  Tasks.get_task/1 with a notify_error call.

  Usage:
      with_task(id_str, from_session_id, "task done", fn id, task ->
        Tasks.update_task_state(task, 3)
        notify_success(from_session_id, "task \#{id} -> done")
      end)
  """
  def with_task(id_str, from_session_id, cmd, fun) when is_binary(id_str) do
    case id_str |> String.trim() |> ToolHelpers.parse_int() do
      nil ->
        notify_error(from_session_id, cmd, {:invalid_id, id_str})

      id ->
        case EyeInTheSky.Tasks.get_task(id) do
          {:ok, task} -> fun.(id, task)
          {:error, :not_found} -> notify_error(from_session_id, cmd, :not_found)
        end
    end
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
