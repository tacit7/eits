defmodule EyeInTheSky.Agents.CmdDispatcher do
  @moduledoc """
  Parses and dispatches EITS-CMD directives from agent text output.

  Protocol: the agent writes a line starting with `EITS-CMD:` anywhere in its
  text. The AgentWorker intercepts these lines before broadcasting to the stream,
  strips them from the visible output, and dispatches them in-process — no HTTP
  round-trips required.

  ## Supported commands

      EITS-CMD: dm --to <session_ref> --message <text>
      EITS-CMD: dm list [--limit <n>]

      EITS-CMD: team broadcast --message <text>

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
                      [--agent <name>] [--provider <claude|codex>] [--yolo]

      EITS-CMD: teams join <team_id> --name <name> [--role <role>]
      EITS-CMD: teams leave <team_id> <member_id>
      EITS-CMD: teams done
      EITS-CMD: teams update-member <team_id> <member_id> --status <status>

      EITS-CMD: channel send <channel_id> --body <text>

  ## Usage from a spawned agent (CLAUDE_CODE_ENTRYPOINT=sdk-cli)

      EITS-CMD: dm --to 1733 --message "done"
      EITS-CMD: dm list
      EITS-CMD: dm list --limit 5
      EITS-CMD: team broadcast --message "Build complete, reviewing output"
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

  alias EyeInTheSky.{ChannelMessages, Commits, Messages, Notes, Notifications, Sessions, Tasks, Teams}
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
      ["dm", args]      -> dispatch_dm(args, from_session_id)
      ["task", args]    -> dispatch_task(args, from_session_id)
      ["note", args]    -> dispatch_note(args, from_session_id)
      ["commit", hash]  -> dispatch_commit(String.trim(hash), from_session_id)
      ["spawn", args]   -> dispatch_spawn(args, from_session_id)
      ["teams", args]   -> dispatch_teams(args, from_session_id)
      ["team", args]    -> dispatch_team(args, from_session_id)
      ["channel", args] -> dispatch_channel(args, from_session_id)
      [unknown]         -> notify_error(from_session_id, unknown, :unknown_command)
      _                 -> notify_error(from_session_id, rest, :unknown_command)
    end
  end

  defp dispatch(line, from_session_id), do: notify_error(from_session_id, "parse", {:malformed_line, line})

  # ---------------------------------------------------------------------------
  # dm
  # ---------------------------------------------------------------------------

  # dm list [--limit <n>] — inject recent inbound DMs back into the agent's context
  defp dispatch_dm("list" <> rest, from_session_id) do
    limit =
      case extract_flag(rest, "--limit") do
        {:ok, n} ->
          case Integer.parse(String.trim(n)) do
            {v, ""} -> min(v, 50)
            _ -> 20
          end

        _ ->
          20
      end

    dms = Messages.list_inbound_dms(from_session_id, limit)

    if dms == [] do
      AgentManager.send_message(from_session_id, "[EITS] dm list: no DMs found")
    else
      lines =
        Enum.map(dms, fn m ->
          ts = Calendar.strftime(m.inserted_at, "%Y-%m-%d %H:%M:%S")
          "[#{ts}] from_session:#{m.from_session_id} — #{m.body}"
        end)

      payload = "[EITS] dm list (#{length(dms)}):\n" <> Enum.join(lines, "\n")
      AgentManager.send_message(from_session_id, payload)
    end

    Logger.info("[CmdDispatcher] dm list for session #{from_session_id}, #{length(dms)} results")
  end

  defp dispatch_dm(args, from_session_id) do
    with {:ok, to_ref} <- extract_flag(args, "--to"),
         {:ok, message} <- extract_flag(args, "--message") do
      case Sessions.get_session(from_session_id) do
        {:ok, from_session} ->
          case Sessions.resolve(to_ref) do
            {:ok, to_session} ->
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
                  to_session_uuid: to_session.uuid
                }
              }

              case AgentManager.send_message(to_session.id, dm_body) do
                {:ok, _} ->
                  case Messages.create_message(attrs) do
                    {:ok, msg} ->
                      EyeInTheSky.Events.session_new_dm(to_session.id, msg)
                      notify_success(from_session_id, "dm sent to session #{to_session.id}")

                    {:error, reason} ->
                      notify_error(from_session_id, "dm persist", reason)
                  end

                {:error, reason} ->
                  notify_error(from_session_id, "dm send", reason)
              end

            {:error, :not_found} ->
              notify_error(from_session_id, "dm", {:target_session_not_found, to_ref})

            err ->
              notify_error(from_session_id, "dm", err)
          end

        {:error, :not_found} ->
          notify_error(from_session_id, "dm", {:sender_session_not_found, from_session_id})

        err ->
          notify_error(from_session_id, "dm", err)
      end
    else
      err -> notify_error(from_session_id, "dm", err)
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
        notify_success(from_session_id, "task created id=#{task.id} title=#{title}")

      {:error, reason} ->
        notify_error(from_session_id, "task create", reason)
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
        notify_success(from_session_id, "task begun id=#{task.id} title=#{title}")

      {:error, reason} ->
        notify_error(from_session_id, "task begin", reason)
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
        notify_success(from_session_id, "task #{id} started (in_progress)")

      _ ->
        notify_error(from_session_id, "task start", {:invalid_id, id_str})
    end
  rescue
    Ecto.NoResultsError -> notify_error(from_session_id, "task start", :not_found)
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
          notify_success(from_session_id, "task #{id} state -> #{state_id}")
        else
          false -> notify_error(from_session_id, "task update", {:not_linked, rest})
          err -> notify_error(from_session_id, "task update", err)
        end

      _ ->
        notify_error(from_session_id, "task update", :expected_id_and_state_id)
    end
  rescue
    Ecto.NoResultsError -> notify_error(from_session_id, "task update", :not_found)
  end

  # task done <id> — shortcut for state 3 (Done)
  defp dispatch_task("done " <> id_str, from_session_id) do
    id_str = String.trim(id_str)

    case Integer.parse(id_str) do
      {id, ""} ->
        if Tasks.task_linked_to_session?(id, from_session_id) do
          task = Tasks.get_task!(id)
          Tasks.update_task_state(task, 3)
          notify_success(from_session_id, "task #{id} -> done")
        else
          notify_error(from_session_id, "task done", {:not_linked, id})
        end

      _ ->
        notify_error(from_session_id, "task done", {:invalid_id, id_str})
    end
  rescue
    Ecto.NoResultsError -> notify_error(from_session_id, "task done", :not_found)
  end

  # task delete <id>
  defp dispatch_task("delete " <> id_str, from_session_id) do
    id_str = String.trim(id_str)

    case Integer.parse(id_str) do
      {id, ""} ->
        if Tasks.task_linked_to_session?(id, from_session_id) do
          task = Tasks.get_task!(id)
          Tasks.delete_task(task)
          notify_success(from_session_id, "task #{id} deleted")
        else
          notify_error(from_session_id, "task delete", {:not_linked, id})
        end

      _ ->
        notify_error(from_session_id, "task delete", {:invalid_id, id_str})
    end
  rescue
    Ecto.NoResultsError -> notify_error(from_session_id, "task delete", :not_found)
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

              notify_success(from_session_id, "task #{id} annotated")
            else
              notify_error(from_session_id, "task annotate", {:not_linked, id})
            end

          _ ->
            notify_error(from_session_id, "task annotate", {:invalid_id, id_str})
        end

      _ ->
        notify_error(from_session_id, "task annotate", :missing_body)
    end
  end

  # task link-session <id> — link current session to an existing task
  defp dispatch_task("link-session " <> id_str, from_session_id) do
    id_str = String.trim(id_str)

    case Integer.parse(id_str) do
      {id, ""} ->
        Tasks.link_session_to_task(id, from_session_id)
        notify_success(from_session_id, "task #{id} linked to session #{from_session_id}")

      _ ->
        notify_error(from_session_id, "task link-session", {:invalid_id, id_str})
    end
  rescue
    Ecto.NoResultsError -> notify_error(from_session_id, "task link-session", :not_found)
  end

  # task unlink-session <id> — unlink current session from a task
  defp dispatch_task("unlink-session " <> id_str, from_session_id) do
    id_str = String.trim(id_str)

    case Integer.parse(id_str) do
      {id, ""} ->
        Tasks.unlink_session_from_task(id, from_session_id)
        notify_success(from_session_id, "task #{id} unlinked from session #{from_session_id}")

      _ ->
        notify_error(from_session_id, "task unlink-session", {:invalid_id, id_str})
    end
  rescue
    Ecto.NoResultsError -> notify_error(from_session_id, "task unlink-session", :not_found)
  end

  # task tag <id> <tag_id>
  defp dispatch_task("tag " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [id_str, tag_id_str] ->
        with {id, ""} <- Integer.parse(String.trim(id_str)),
             {tag_id, ""} <- Integer.parse(String.trim(tag_id_str)),
             true <- Tasks.task_linked_to_session?(id, from_session_id) do
          Tasks.link_tag_to_task(id, tag_id)
          notify_success(from_session_id, "task #{id} tagged with #{tag_id}")
        else
          false -> notify_error(from_session_id, "task tag", {:not_linked, id_str})
          _ -> notify_error(from_session_id, "task tag", {:invalid_id_or_tag_id, rest})
        end

      _ ->
        notify_error(from_session_id, "task tag", :expected_id_and_tag_id)
    end
  rescue
    Ecto.NoResultsError -> notify_error(from_session_id, "task tag", :not_found)
  end

  defp dispatch_task(unknown, from_session_id),
    do: notify_error(from_session_id, "task", {:unknown_subcommand, unknown})

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
              notify_success(from_session_id, "note added to task #{id}")
            else
              notify_error(from_session_id, "note task", {:not_linked, id})
            end

          _ ->
            notify_error(from_session_id, "note task", {:invalid_id, id_str})
        end

      _ ->
        notify_error(from_session_id, "note task", :missing_body)
    end
  end

  # note <body> — note on the current session
  defp dispatch_note(body, from_session_id) when body != "" do
    Notes.create_note(%{body: body, parent_id: from_session_id, parent_type: "session"})
    notify_success(from_session_id, "note added to session #{from_session_id}")
  end

  defp dispatch_note(_, from_session_id), do: notify_error(from_session_id, "note", :empty_body)

  # ---------------------------------------------------------------------------
  # commit
  # ---------------------------------------------------------------------------

  defp dispatch_commit(hash, from_session_id) when hash != "" do
    case Commits.create_commit(%{commit_hash: hash, session_id: from_session_id}) do
      {:ok, _} ->
        notify_success(from_session_id, "commit #{hash} logged")

      {:error, reason} ->
        notify_error(from_session_id, "commit", reason)
    end
  end

  defp dispatch_commit(_, from_session_id), do: notify_error(from_session_id, "commit", :empty_hash)

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
      opts = put_optional_flag(opts, args, "--provider",     :agent_type)

      opts = if String.contains?(args, "--yolo"),
        do: Keyword.put(opts, :bypass_sandbox, true),
        else: opts

      case AgentManager.create_agent(opts) do
        {:ok, %{agent: agent, session: new_session}} ->
          notify_success(from_session_id, "spawned agent=#{agent.id} session=#{new_session.id} uuid=#{new_session.uuid}")

        {:error, reason} ->
          notify_error(from_session_id, "spawn", reason)
      end
    else
      err -> notify_error(from_session_id, "spawn (missing --instructions)", err)
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
              notify_success(from_session_id, "joined team #{team_id} as #{member.name} (member_id=#{member.id})")

            {:error, reason} ->
              notify_error(from_session_id, "teams join", reason)
          end
        else
          _ -> notify_error(from_session_id, "teams join", :invalid_team_id_or_missing_name)
        end

      _ ->
        notify_error(from_session_id, "teams join", :expected_team_id_and_name)
    end
  end

  # teams leave <team_id> <member_id>
  defp dispatch_teams("leave " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [_team_id_str, member_id_str] ->
        case Integer.parse(String.trim(member_id_str)) do
          {member_id, ""} ->
            case Teams.get_member(member_id) do
              nil ->
                notify_error(from_session_id, "teams leave", {:member_not_found, member_id})

              member ->
                Teams.leave_team(member)
                notify_success(from_session_id, "member #{member_id} left team")
            end

          _ ->
            notify_error(from_session_id, "teams leave", {:invalid_member_id, member_id_str})
        end

      _ ->
        notify_error(from_session_id, "teams leave", :expected_team_id_and_member_id)
    end
  end

  # teams done — mark current session's team memberships as done
  defp dispatch_teams("done" <> _, from_session_id) do
    Teams.mark_member_done_by_session(from_session_id)
    notify_success(from_session_id, "teams done for session #{from_session_id}")
  end

  # teams update-member <team_id> <member_id> --status <status>
  defp dispatch_teams("update-member " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 3) do
      [_team_id_str, member_id_str | tail] ->
        args = List.first(tail, "")

        with {member_id, ""} <- Integer.parse(String.trim(member_id_str)),
             {:ok, status} <- extract_flag(args, "--status") do
          case Teams.get_member(member_id) do
            nil ->
              notify_error(from_session_id, "teams update-member", {:member_not_found, member_id})

            member ->
              Teams.update_member_status(member, status)
              notify_success(from_session_id, "team member #{member_id} status -> #{status}")
          end
        else
          _ -> notify_error(from_session_id, "teams update-member", :invalid_member_id_or_missing_status)
        end

      _ ->
        notify_error(from_session_id, "teams update-member", :expected_team_id_member_id_and_status)
    end
  end

  defp dispatch_teams(unknown, from_session_id),
    do: notify_error(from_session_id, "teams", {:unknown_subcommand, unknown})

  # ---------------------------------------------------------------------------
  # team (singular) — agent-scoped team commands
  # ---------------------------------------------------------------------------

  # team broadcast --message <text>
  # Sends a DM to every other active member in all teams the calling session belongs to.
  defp dispatch_team("broadcast" <> rest, from_session_id) do
    case extract_flag(rest, "--message") do
      {:ok, message} ->
        members = Teams.list_broadcast_targets(from_session_id)

        {:ok, from_session} = Sessions.get_session(from_session_id)
        sender_name = from_session.name || "session:#{from_session.uuid}"
        dm_body = "[team broadcast] from #{sender_name}: #{message}"

        Enum.each(members, fn member ->
          Task.start(fn ->
            AgentManager.send_message(member.session_id, dm_body)
          end)
        end)

        notify_success(from_session_id, "team broadcast sent to #{length(members)} members")

      _ ->
        notify_error(from_session_id, "team broadcast", :missing_message_flag)
    end
  end

  defp dispatch_team(unknown, from_session_id),
    do: notify_error(from_session_id, "team", {:unknown_subcommand, unknown})

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
              notify_success(from_session_id, "channel #{channel_id} message sent (id=#{msg.id})")

            {:error, reason} ->
              notify_error(from_session_id, "channel send", reason)
          end
        else
          _ -> notify_error(from_session_id, "channel send", :invalid_channel_id_or_missing_body)
        end

      _ ->
        notify_error(from_session_id, "channel send", :expected_channel_id_and_body)
    end
  end

  defp dispatch_channel(unknown, from_session_id),
    do: notify_error(from_session_id, "channel", {:unknown_subcommand, unknown})

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

  # ---------------------------------------------------------------------------
  # Error surfacing
  # ---------------------------------------------------------------------------

  # Sends a success acknowledgement back to the originating agent session
  # so it can use returned IDs (e.g. task ID) in follow-up commands.
  defp notify_success(from_session_id, msg) do
    Logger.info("[CmdDispatcher] #{msg}")

    if from_session_id do
      Task.start(fn -> AgentManager.send_message(from_session_id, "[EITS-CMD ok] #{msg}") end)
    end

    :ok
  end

  # Logs the error, creates a persistent notification visible in the UI,
  # and DMs the error back to the originating agent session so it can react.
  defp notify_error(from_session_id, cmd, reason) do
    msg = "[EITS-CMD error] #{cmd}: #{inspect(reason)}"
    Logger.warning("[CmdDispatcher] #{msg}")

    Notifications.notify("EITS-CMD #{cmd} failed",
      body: inspect(reason),
      category: :agent,
      resource: {"session", to_string(from_session_id)}
    )

    if from_session_id do
      Task.start(fn -> AgentManager.send_message(from_session_id, msg) end)
    end

    :ok
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
