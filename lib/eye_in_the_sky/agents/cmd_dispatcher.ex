defmodule EyeInTheSky.Agents.CmdDispatcher do
  @moduledoc """
  Parses and dispatches EITS-CMD directives from agent text output.

  Protocol: the agent writes a line starting with `EITS-CMD:` anywhere in its
  text. The AgentWorker intercepts these lines before broadcasting to the stream,
  strips them from the visible output, and dispatches them in-process — no HTTP
  round-trips required.

  ## Supported commands

      EITS-CMD: dm --to <session_uuid> --message <text>

      EITS-CMD: task create <title>
      EITS-CMD: task begin <title>
      EITS-CMD: task update <id> <state_id>
      EITS-CMD: task done <id>
      EITS-CMD: task annotate <id> <body>

      EITS-CMD: note <body>
      EITS-CMD: note task <id> <body>

      EITS-CMD: commit <hash>

      EITS-CMD: spawn --instructions <text> [--description <text>] [--model <model>]

  ## Usage from a spawned agent (CLAUDE_CODE_ENTRYPOINT=cli)

      EITS-CMD: dm --to 0c77344b-52bc-4c3d-97a1-cf3c421cb325 --message "done"
      EITS-CMD: commit abc1234
      EITS-CMD: task begin Fix broken import in dm_page
      EITS-CMD: task done 1234
      EITS-CMD: note Deployed hotfix for shift_zone crash
      EITS-CMD: spawn --instructions "Review PR #38 and DM me back" --model sonnet
  """

  require Logger

  alias EyeInTheSky.{Commits, Messages, Notes, Sessions, Tasks}
  alias EyeInTheSky.Agents.AgentManager

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
  # Dispatch router
  # ---------------------------------------------------------------------------

  defp dispatch(@cmd_prefix <> rest, from_session_id) do
    case String.split(String.trim(rest), " ", parts: 2) do
      ["dm", args]     -> dispatch_dm(args, from_session_id)
      ["task", args]   -> dispatch_task(args, from_session_id)
      ["note", args]   -> dispatch_note(args, from_session_id)
      ["commit", hash] -> dispatch_commit(String.trim(hash), from_session_id)
      ["spawn", args]  -> dispatch_spawn(args, from_session_id)
      _                -> Logger.warning("[CmdDispatcher] Unknown command: #{rest}")
    end
  end

  defp dispatch(line, _), do: Logger.warning("[CmdDispatcher] Malformed line: #{line}")

  # ---------------------------------------------------------------------------
  # dm
  # ---------------------------------------------------------------------------

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

      case AgentManager.send_message(to_session.id, dm_body) do
        {:ok, _} ->
          case Messages.create_message(attrs) do
            {:ok, msg} ->
              EyeInTheSky.Events.session_new_dm(to_session.id, msg)
              Logger.info("[CmdDispatcher] dm #{from_session_id} -> #{to_uuid}")

            {:error, reason} ->
              Logger.warning("[CmdDispatcher] dm persist failed: #{inspect(reason)}")
          end

        {:error, reason} ->
          Logger.warning("[CmdDispatcher] dm send failed (not persisted): #{inspect(reason)}")
      end
    else
      err -> Logger.warning("[CmdDispatcher] dm failed: #{inspect(err)}")
    end
  end

  # ---------------------------------------------------------------------------
  # task
  # ---------------------------------------------------------------------------

  # task create <title>
  defp dispatch_task("create " <> title, from_session_id) do
    title = String.trim(title)
    session = get_session!(from_session_id)

    case Tasks.create_task(%{
           title: title,
           state_id: 1,
           project_id: session && session.project_id
         }) do
      {:ok, task} ->
        Tasks.link_session_to_task(task.id, from_session_id)
        Logger.info("[CmdDispatcher] task created id=#{task.id} title=#{title}")

      {:error, reason} ->
        Logger.warning("[CmdDispatcher] task create failed: #{inspect(reason)}")
    end
  end

  # task begin <title> — create + move to In Progress
  defp dispatch_task("begin " <> title, from_session_id) do
    title = String.trim(title)
    session = get_session!(from_session_id)

    case Tasks.create_task(%{
           title: title,
           state_id: 2,
           project_id: session && session.project_id
         }) do
      {:ok, task} ->
        Tasks.link_session_to_task(task.id, from_session_id)
        Logger.info("[CmdDispatcher] task begun id=#{task.id} title=#{title}")

      {:error, reason} ->
        Logger.warning("[CmdDispatcher] task begin failed: #{inspect(reason)}")
    end
  end

  # task update <id> <state_id>
  defp dispatch_task("update " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [id_str, state_str] ->
        with {id, ""} <- Integer.parse(String.trim(id_str)),
             {state_id, ""} <- Integer.parse(String.trim(state_str)),
             true <- Tasks.task_linked_to_session?(id, from_session_id),
             task <- Tasks.get_task!(id) do
          Tasks.update_task_state(task, state_id)
          Logger.info("[CmdDispatcher] task #{id} state -> #{state_id}")
        else
          false -> Logger.warning("[CmdDispatcher] task update: task #{rest} not linked to session #{from_session_id}")
          err -> Logger.warning("[CmdDispatcher] task update failed: #{inspect(err)}")
        end

      _ ->
        Logger.warning("[CmdDispatcher] task update: expected <id> <state_id>")
    end
  rescue
    _ -> Logger.warning("[CmdDispatcher] task update: task not found")
  end

  # task done <id> — shortcut for state 3 (Done)
  defp dispatch_task("done " <> id_str, from_session_id) do
    id_str = String.trim(id_str)

    case Integer.parse(id_str) do
      {id, ""} ->
        if Tasks.task_linked_to_session?(id, from_session_id) do
          task = Tasks.get_task!(id)
          Tasks.update_task_state(task, 3)
          Logger.info("[CmdDispatcher] task #{id} -> done")
        else
          Logger.warning("[CmdDispatcher] task done: task #{id} not linked to session #{from_session_id}")
        end

      _ ->
        Logger.warning("[CmdDispatcher] task done: invalid id '#{id_str}'")
    end
  rescue
    _ -> Logger.warning("[CmdDispatcher] task done: task not found")
  end

  # task annotate <id> <body>
  defp dispatch_task("annotate " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [id_str, body] ->
        case Integer.parse(String.trim(id_str)) do
          {id, ""} ->
            if Tasks.task_linked_to_session?(id, from_session_id) do
              Notes.create_note(%{
                title: "Agent annotation",
                body: body,
                parent_id: id,
                parent_type: "task"
              })

              Logger.info("[CmdDispatcher] task #{id} annotated")
            else
              Logger.warning("[CmdDispatcher] task annotate: task #{id} not linked to session #{from_session_id}")
            end

          _ ->
            Logger.warning("[CmdDispatcher] task annotate: invalid id '#{id_str}'")
        end

      _ ->
        Logger.warning("[CmdDispatcher] task annotate: missing body")
    end
  end

  defp dispatch_task(unknown, _),
    do: Logger.warning("[CmdDispatcher] Unknown task sub-command: #{unknown}")

  # ---------------------------------------------------------------------------
  # note
  # ---------------------------------------------------------------------------

  # note task <id> <body>
  defp dispatch_note("task " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [id_str, body] ->
        case Integer.parse(String.trim(id_str)) do
          {id, ""} ->
            if Tasks.task_linked_to_session?(id, from_session_id) do
              Notes.create_note(%{body: body, parent_id: id, parent_type: "task"})
              Logger.info("[CmdDispatcher] note on task #{id}")
            else
              Logger.warning("[CmdDispatcher] note task: task #{id} not linked to session #{from_session_id}")
            end

          _ ->
            Logger.warning("[CmdDispatcher] note task: invalid id '#{id_str}'")
        end

      _ ->
        Logger.warning("[CmdDispatcher] note task: missing body")
    end
  end

  # note <body> — note on the current session
  defp dispatch_note(body, from_session_id) when body != "" do
    Notes.create_note(%{body: body, parent_id: from_session_id, parent_type: "session"})
    Logger.info("[CmdDispatcher] note on session #{from_session_id}")
  end

  defp dispatch_note(_, _), do: Logger.warning("[CmdDispatcher] note: empty body")

  # ---------------------------------------------------------------------------
  # commit
  # ---------------------------------------------------------------------------

  defp dispatch_commit(hash, from_session_id) when hash != "" do
    case Commits.create_commit(%{commit_hash: hash, session_id: from_session_id}) do
      {:ok, _} ->
        Logger.info("[CmdDispatcher] commit #{hash} logged for session #{from_session_id}")

      {:error, reason} ->
        Logger.warning("[CmdDispatcher] commit failed: #{inspect(reason)}")
    end
  end

  defp dispatch_commit(_, _), do: Logger.warning("[CmdDispatcher] commit: empty hash")

  # ---------------------------------------------------------------------------
  # spawn
  # ---------------------------------------------------------------------------

  defp dispatch_spawn(args, from_session_id) do
    with {:ok, instructions} <- extract_flag(args, "--instructions") do
      session = get_session!(from_session_id)
      description = case extract_flag(args, "--description") do
        {:ok, d} -> d
        _ -> "Spawned by session #{from_session_id}"
      end
      model = case extract_flag(args, "--model") do
        {:ok, m} -> m
        _ -> nil
      end

      opts = [
        instructions: instructions,
        description: description,
        project_id: session && session.project_id,
        project_path: session && session.git_worktree_path
      ]
      opts = if model, do: Keyword.put(opts, :model, model), else: opts

      case AgentManager.create_agent(opts) do
        {:ok, %{agent: agent, session: new_session}} ->
          Logger.info("[CmdDispatcher] spawned agent=#{agent.id} session=#{new_session.id} from=#{from_session_id}")

        {:error, reason} ->
          Logger.warning("[CmdDispatcher] spawn failed: #{inspect(reason)}")
      end
    else
      err -> Logger.warning("[CmdDispatcher] spawn: missing --instructions flag: #{inspect(err)}")
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp get_session!(session_id) do
    case Sessions.get_session(session_id) do
      {:ok, session} -> session
      _ -> nil
    end
  end

  # Handles: --flag "quoted value"  or  --flag multi word value (to next flag or EOL)
  defp extract_flag(str, flag) do
    escaped = Regex.escape(flag)

    case Regex.run(~r/#{escaped}\s+"([^"]*)"/, str) do
      [_, value] ->
        {:ok, value}

      nil ->
        # Capture from the flag to the next --flag or end of string
        case Regex.run(~r/#{escaped}\s+(.+?)(?=\s+--\S|\z)/s, str) do
          [_, value] -> {:ok, String.trim(value)}
          nil -> {:error, {:missing_flag, flag}}
        end
    end
  end
end
