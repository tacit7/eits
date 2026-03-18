defmodule EyeInTheSkyWeb.Agents.CmdDispatcher do
  @moduledoc """
  Parses and dispatches EITS-CMD directives from agent text output.

  Protocol: the agent writes a line starting with `EITS-CMD:` anywhere in its
  text. The AgentWorker intercepts these lines before broadcasting to the stream,
  strips them from the visible output, and dispatches them in-process — no HTTP
  round-trips required.

  ## Supported commands

      EITS-CMD: dm --to <session_uuid> --message <text>
      EITS-CMD: task done <id>
      EITS-CMD: task annotate <id> <body>

  ## Usage from an agent

      EITS-CMD: dm --to 0c77344b-52bc-4c3d-97a1-cf3c421cb325 --message "LGTM, no issues found"
      EITS-CMD: task done 1234
      EITS-CMD: task annotate 1234 Fixed the broken import in dm_page.ex
  """

  require Logger

  alias EyeInTheSkyWeb.{Messages, Notes, Sessions, Tasks}
  alias EyeInTheSkyWeb.Agents.AgentManager

  @cmd_prefix "EITS-CMD:"

  @doc """
  Scans text content for EITS-CMD lines.
  Returns `{cmd_lines, clean_text}` where `clean_text` has CMD lines stripped.
  """
  @spec extract_commands(String.t()) :: {[String.t()], String.t()}
  def extract_commands(text) when is_binary(text) do
    lines = String.split(text, "\n")

    {cmd_lines, clean_lines} =
      Enum.split_with(lines, fn line ->
        String.starts_with?(String.trim(line), @cmd_prefix)
      end)

    {cmd_lines, Enum.join(clean_lines, "\n")}
  end

  @doc """
  Dispatches a list of EITS-CMD lines in the context of the given session.
  Each command is dispatched asynchronously to avoid blocking the worker.
  """
  @spec dispatch_all([String.t()], integer()) :: :ok
  def dispatch_all(cmd_lines, from_session_id) do
    Enum.each(cmd_lines, fn line ->
      Task.start(fn -> dispatch(String.trim(line), from_session_id) end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Private dispatch
  # ---------------------------------------------------------------------------

  defp dispatch(@cmd_prefix <> rest, from_session_id) do
    case String.split(String.trim(rest), " ", parts: 2) do
      ["dm", args] -> dispatch_dm(args, from_session_id)
      ["task", args] -> dispatch_task(args, from_session_id)
      _ -> Logger.warning("[CmdDispatcher] Unknown command: #{rest}")
    end
  end

  defp dispatch(line, _), do: Logger.warning("[CmdDispatcher] Malformed line: #{line}")

  # --- dm ---

  defp dispatch_dm(args, from_session_id) do
    with {:ok, to_uuid} <- extract_flag(args, "--to"),
         {:ok, message} <- extract_flag(args, "--message"),
         {:ok, from_session} <- Sessions.get_session(from_session_id),
         {:ok, to_session} <- Sessions.get_session_by_uuid(to_uuid) do
      sender_name = from_session.name || "session:#{from_session.uuid}"
      dm_body = "DM from:#{sender_name} (session:#{from_session.uuid}) #{message}"

      attrs = %{
        uuid: Ecto.UUID.generate(),
        session_id: to_session.id,
        from_session_id: from_session.id,
        to_session_id: to_session.id,
        body: dm_body,
        sender_role: "agent",
        recipient_role: "agent",
        direction: "inbound",
        status: "sent",
        provider: "claude",
        metadata: %{
          sender_name: sender_name,
          from_session_uuid: from_session.uuid,
          to_session_uuid: to_uuid
        }
      }

      AgentManager.send_message(to_session.id, dm_body)

      case Messages.create_message(attrs) do
        {:ok, msg} ->
          EyeInTheSkyWeb.Events.session_new_dm(to_session.id, msg)
          Logger.info("[CmdDispatcher] dm #{from_session_id} -> #{to_uuid}")

        {:error, reason} ->
          Logger.warning("[CmdDispatcher] dm persist failed: #{inspect(reason)}")
      end
    else
      err -> Logger.warning("[CmdDispatcher] dm failed: #{inspect(err)}")
    end
  end

  # --- task ---

  defp dispatch_task("done " <> id_str, _from_session_id) do
    id_str = String.trim(id_str)

    case Integer.parse(id_str) do
      {id, ""} ->
        case Tasks.get_task!(id) do
          nil ->
            Logger.warning("[CmdDispatcher] task done: #{id} not found")

          task ->
            Tasks.update_task_state(task, 4)
            Logger.info("[CmdDispatcher] task #{id} -> done")
        end

      _ ->
        Logger.warning("[CmdDispatcher] task done: invalid id '#{id_str}'")
    end
  rescue
    _ -> Logger.warning("[CmdDispatcher] task done: #{id_str} not found")
  end

  defp dispatch_task("annotate " <> rest, _from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [id_str, body] ->
        case Integer.parse(String.trim(id_str)) do
          {id, ""} ->
            Notes.create_note(%{
              title: "Agent annotation",
              body: body,
              parent_id: id,
              parent_type: "task"
            })

            Logger.info("[CmdDispatcher] task #{id} annotated")

          _ ->
            Logger.warning("[CmdDispatcher] task annotate: invalid id '#{id_str}'")
        end

      _ ->
        Logger.warning("[CmdDispatcher] task annotate: missing body in '#{rest}'")
    end
  end

  defp dispatch_task(unknown, _),
    do: Logger.warning("[CmdDispatcher] Unknown task sub-command: #{unknown}")

  # ---------------------------------------------------------------------------
  # Flag parser
  # ---------------------------------------------------------------------------

  # Handles: --flag "quoted value"  or  --flag unquoted_value
  defp extract_flag(str, flag) do
    escaped = Regex.escape(flag)

    case Regex.run(~r/#{escaped}\s+"([^"]*)"/, str) do
      [_, value] ->
        {:ok, value}

      nil ->
        case Regex.run(~r/#{escaped}\s+(\S+)/, str) do
          [_, value] -> {:ok, value}
          nil -> {:error, {:missing_flag, flag}}
        end
    end
  end
end
