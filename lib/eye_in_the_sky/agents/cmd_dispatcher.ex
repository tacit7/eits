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
      EITS-CMD: task start <id>
      EITS-CMD: task update <id> <state_id>
      EITS-CMD: task done <id>
      EITS-CMD: task delete <id>
      EITS-CMD: task annotate <id> <body>
      EITS-CMD: task link-session <id>
      EITS-CMD: task unlink-session <id>
      EITS-CMD: task tag <id> <tag_id>

      EITS-CMD: note <body>
      EITS-CMD: note task <id> <body>

      EITS-CMD: commit <hash>

      EITS-CMD: spawn --instructions <text> [--description <text>] [--model <model>]
                      [--worktree <branch>] [--effort-level <level>]
                      [--team-name <name>] [--member-name <alias>]
                      [--agent <name>] [--yolo]

      EITS-CMD: teams join <team_id> --name <name> [--role <role>]
      EITS-CMD: teams leave <team_id> <member_id>
      EITS-CMD: teams done
      EITS-CMD: teams update-member <team_id> <member_id> --status <status>

      EITS-CMD: channel send <channel_id> --body <text>

  ## Usage from a spawned agent (CLAUDE_CODE_ENTRYPOINT=sdk-cli)

      EITS-CMD: dm --to 0c77344b-52bc-4c3d-97a1-cf3c421cb325 --message "done"
      EITS-CMD: commit abc1234
      EITS-CMD: task begin Fix broken import in dm_page
      EITS-CMD: task start 1234
      EITS-CMD: task done 1234
      EITS-CMD: task delete 1234
      EITS-CMD: task link-session 1234
      EITS-CMD: task tag 1234 5
      EITS-CMD: note Deployed hotfix for shift_zone crash
      EITS-CMD: spawn --instructions "Review PR #38 and DM me back" --model sonnet --worktree my-feature
      EITS-CMD: teams join 7 --name worker-1 --role worker
      EITS-CMD: teams done
      EITS-CMD: channel send 3 --body "Build complete"
  """

  require Logger

  alias EyeInTheSky.{ChannelMessages, Commits, Messages, Notes, Sessions, Tasks, Teams}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Teams.TeamMember

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
      ["dm", args]      -> dispatch_dm(args, from_session_id)
      ["task", args]    -> dispatch_task(args, from_session_id)
      ["note", args]    -> dispatch_note(args, from_session_id)
      ["commit", hash]  -> dispatch_commit(String.trim(hash), from_session_id)
      ["spawn", args]   -> dispatch_spawn(args, from_session_id)
      ["teams", args]   -> dispatch_teams(args, from_session_id)
      ["channel", args] -> dispatch_channel(args, from_session_id)
      _                 -> Logger.warning("[CmdDispatcher] Unknown command: #{rest}")
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

  # task start <id> — move existing task to In Progress and link session
  defp dispatch_task("start " <> id_str, from_session_id) do
    id_str = String.trim(id_str)

    case Integer.parse(id_str) do
      {id, ""} ->
        task = Tasks.get_task!(id)
        Tasks.update_task_state(task, 2)
        Tasks.link_session_to_task(id, from_session_id)
        Logger.info("[CmdDispatcher] task #{id} -> in_progress")

      _ ->
        Logger.warning("[CmdDispatcher] task start: invalid id '#{id_str}'")
    end
  rescue
    _ -> Logger.warning("[CmdDispatcher] task start: task not found")
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

  # task delete <id>
  defp dispatch_task("delete " <> id_str, from_session_id) do
    id_str = String.trim(id_str)

    case Integer.parse(id_str) do
      {id, ""} ->
        if Tasks.task_linked_to_session?(id, from_session_id) do
          task = Tasks.get_task!(id)
          Tasks.delete_task(task)
          Logger.info("[CmdDispatcher] task #{id} deleted")
        else
          Logger.warning("[CmdDispatcher] task delete: task #{id} not linked to session #{from_session_id}")
        end

      _ ->
        Logger.warning("[CmdDispatcher] task delete: invalid id '#{id_str}'")
    end
  rescue
    _ -> Logger.warning("[CmdDispatcher] task delete: task not found")
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

  # task link-session <id> — link current session to an existing task
  defp dispatch_task("link-session " <> id_str, from_session_id) do
    id_str = String.trim(id_str)

    case Integer.parse(id_str) do
      {id, ""} ->
        Tasks.link_session_to_task(id, from_session_id)
        Logger.info("[CmdDispatcher] task #{id} linked to session #{from_session_id}")

      _ ->
        Logger.warning("[CmdDispatcher] task link-session: invalid id '#{id_str}'")
    end
  rescue
    _ -> Logger.warning("[CmdDispatcher] task link-session: task not found")
  end

  # task unlink-session <id> — unlink current session from a task
  defp dispatch_task("unlink-session " <> id_str, from_session_id) do
    id_str = String.trim(id_str)

    case Integer.parse(id_str) do
      {id, ""} ->
        Tasks.unlink_session_from_task(id, from_session_id)
        Logger.info("[CmdDispatcher] task #{id} unlinked from session #{from_session_id}")

      _ ->
        Logger.warning("[CmdDispatcher] task unlink-session: invalid id '#{id_str}'")
    end
  rescue
    _ -> Logger.warning("[CmdDispatcher] task unlink-session: task not found")
  end

  # task tag <id> <tag_id>
  defp dispatch_task("tag " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [id_str, tag_id_str] ->
        with {id, ""} <- Integer.parse(String.trim(id_str)),
             {tag_id, ""} <- Integer.parse(String.trim(tag_id_str)),
             true <- Tasks.task_linked_to_session?(id, from_session_id) do
          Tasks.link_tag_to_task(id, tag_id)
          Logger.info("[CmdDispatcher] task #{id} tagged with #{tag_id}")
        else
          false -> Logger.warning("[CmdDispatcher] task tag: task #{id_str} not linked to session #{from_session_id}")
          _ -> Logger.warning("[CmdDispatcher] task tag: invalid id or tag_id in '#{rest}'")
        end

      _ ->
        Logger.warning("[CmdDispatcher] task tag: expected <id> <tag_id>")
    end
  rescue
    _ -> Logger.warning("[CmdDispatcher] task tag: task not found")
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

      opts = [
        instructions: instructions,
        description: description,
        project_id: session && session.project_id,
        project_path: session && session.git_worktree_path
      ]

      opts = put_optional_flag(opts, args, "--model",        :model)
      opts = put_optional_flag(opts, args, "--worktree",     :worktree)
      opts = put_optional_flag(opts, args, "--effort-level", :effort_level)
      opts = put_optional_flag(opts, args, "--team-name",    :team_name)
      opts = put_optional_flag(opts, args, "--member-name",  :member_name)
      opts = put_optional_flag(opts, args, "--agent",        :agent)

      opts = if String.contains?(args, "--yolo"),
        do: Keyword.put(opts, :bypass_sandbox, true),
        else: opts

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
  # teams
  # ---------------------------------------------------------------------------

  # teams join <team_id> --name <name> [--role <role>]
  defp dispatch_teams("join " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [team_id_str | tail] ->
        args = List.first(tail, "")

        with {team_id, ""} <- Integer.parse(String.trim(team_id_str)),
             {:ok, name} <- extract_flag(args, "--name") do
          session = get_session!(from_session_id)
          role = case extract_flag(args, "--role") do
            {:ok, r} -> r
            _ -> "member"
          end

          attrs = %{
            team_id: team_id,
            name: name,
            role: role,
            session_id: from_session_id,
            agent_id: session && session.agent_id
          }

          case Teams.join_team(attrs) do
            {:ok, member} ->
              Logger.info("[CmdDispatcher] session #{from_session_id} joined team #{team_id} as #{member.name}")

            {:error, reason} ->
              Logger.warning("[CmdDispatcher] teams join failed: #{inspect(reason)}")
          end
        else
          _ -> Logger.warning("[CmdDispatcher] teams join: invalid team_id or missing --name")
        end

      _ ->
        Logger.warning("[CmdDispatcher] teams join: expected <team_id> --name <name>")
    end
  end

  # teams leave <team_id> <member_id>
  defp dispatch_teams("leave " <> rest, _from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [_team_id_str, member_id_str] ->
        case Integer.parse(String.trim(member_id_str)) do
          {member_id, ""} ->
            case EyeInTheSky.Repo.get(TeamMember, member_id) do
              nil ->
                Logger.warning("[CmdDispatcher] teams leave: member #{member_id} not found")

              member ->
                Teams.leave_team(member)
                Logger.info("[CmdDispatcher] member #{member_id} left team")
            end

          _ ->
            Logger.warning("[CmdDispatcher] teams leave: invalid member_id '#{member_id_str}'")
        end

      _ ->
        Logger.warning("[CmdDispatcher] teams leave: expected <team_id> <member_id>")
    end
  end

  # teams done — mark current session's team memberships as done
  defp dispatch_teams("done", from_session_id) do
    Teams.mark_member_done_by_session(from_session_id)
    Logger.info("[CmdDispatcher] teams done for session #{from_session_id}")
  end

  defp dispatch_teams("done" <> _, from_session_id) do
    Teams.mark_member_done_by_session(from_session_id)
    Logger.info("[CmdDispatcher] teams done for session #{from_session_id}")
  end

  # teams update-member <team_id> <member_id> --status <status>
  defp dispatch_teams("update-member " <> rest, _from_session_id) do
    case String.split(rest, " ", parts: 3) do
      [_team_id_str, member_id_str | tail] ->
        args = List.first(tail, "")

        with {member_id, ""} <- Integer.parse(String.trim(member_id_str)),
             {:ok, status} <- extract_flag(args, "--status") do
          case EyeInTheSky.Repo.get(TeamMember, member_id) do
            nil ->
              Logger.warning("[CmdDispatcher] teams update-member: member #{member_id} not found")

            member ->
              Teams.update_member_status(member, status)
              Logger.info("[CmdDispatcher] team member #{member_id} status -> #{status}")
          end
        else
          _ -> Logger.warning("[CmdDispatcher] teams update-member: invalid member_id or missing --status")
        end

      _ ->
        Logger.warning("[CmdDispatcher] teams update-member: expected <team_id> <member_id> --status <status>")
    end
  end

  defp dispatch_teams(unknown, _),
    do: Logger.warning("[CmdDispatcher] Unknown teams sub-command: #{unknown}")

  # ---------------------------------------------------------------------------
  # channel
  # ---------------------------------------------------------------------------

  # channel send <channel_id> --body <text>
  defp dispatch_channel("send " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [channel_id_str | tail] ->
        args = List.first(tail, "")

        with {channel_id, ""} <- Integer.parse(String.trim(channel_id_str)),
             {:ok, body} <- extract_flag(args, "--body") do
          session = get_session!(from_session_id)

          attrs = %{
            channel_id: channel_id,
            session_id: from_session_id,
            agent_id: session && session.agent_id,
            body: body,
            sender_role: "agent"
          }

          case ChannelMessages.send_channel_message(attrs) do
            {:ok, msg} ->
              Logger.info("[CmdDispatcher] channel #{channel_id} message id=#{msg.id} from session #{from_session_id}")

            {:error, reason} ->
              Logger.warning("[CmdDispatcher] channel send failed: #{inspect(reason)}")
          end
        else
          _ -> Logger.warning("[CmdDispatcher] channel send: invalid channel_id or missing --body")
        end

      _ ->
        Logger.warning("[CmdDispatcher] channel send: expected <channel_id> --body <text>")
    end
  end

  defp dispatch_channel(unknown, _),
    do: Logger.warning("[CmdDispatcher] Unknown channel sub-command: #{unknown}")

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp get_session!(session_id) do
    case Sessions.get_session(session_id) do
      {:ok, session} -> session
      _ -> nil
    end
  end

  defp put_optional_flag(opts, args, flag, key) do
    case extract_flag(args, flag) do
      {:ok, value} -> Keyword.put(opts, key, value)
      _ -> opts
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
